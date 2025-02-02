#!/bin/bash

set -e

function print_usage() {
  echo "
    Usage: $(basename $0) [OPTIONS]

    Options:
      -i  --init                  Initializes the duplicacy storage, passing in the path to the directory
      -n  --name                  Storage name to uniquely identify the backup repo
      -p, --proxy <args>          Forwards the arguments to duplicacy but with env vars exported
      -h, --help                  Display usage
  "
}

function get_args() {
  while getopts 'i:n:p:h' OPTION; do
    case "$OPTION" in
      i)
        BACKUP_DIR="$OPTARG"
        ;;
      n)
        STORAGE_NAME="$OPTARG"
        ;;
      h)
        print_usage
        exit 0
        ;;
      ?)
        print_usage
        exit 1
        ;;
    esac
  done
  shift "$(($OPTIND -1))"

  if [[ -z "$BACKUP_DIR" ]]; then
    echo "Error: backup directory must accompany the -i option"
    exit 1
  fi
  if [[ -n "$STORAGE_NAME" ]]; then
    echo "Error: name must be specified with the -n option"
    exit 1
  fi
}

# Export all entries in the .env file as environment variables
function load_env_file() {
  # For Windows, \r can sometimes get appended to the values
  # so we need to strip them from the exports
  export $(grep -v '^#' .env | tr -d '\r' | xargs)

  assert_env_var "B2_KEY_ID"
  assert_env_var "B2_APPLICATION_KEY"
  assert_env_var "B2_BUCKET_NAME"
  assert_env_var "PTERODACTYL_TOKEN"
  assert_env_var "PTERODACTYL_SERVER_IDENTIFIER"
  assert_env_var "PTERODACTYL_BASE_URL"
  assert_env_var "DISCORD_WEBHOOK_URL"

  # Export key to env to avoid interactive authentication when
  # initializing the repo.
  #
  # Normally the key is DUPLICACY_B2_ID, but for non-default storage
  # it becomes DUPLICACY_<STORAGENAME>_B2_ID in all uppercase
  # See https://github.com/gilbertchen/duplicacy/wiki/Managing-Passwords
  export DUPLICACY_MINECRAFT_B2_ID=$B2_KEY_ID
  export DUPLICACY_MINECRAFT_B2_KEY=$B2_APPLICATION_KEY
}

# Exits if the given command is missing
function assert_command() {
  local command="$1"

  if ! command -v "$command" 2>&1 >/dev/null; then
      echo "Error: $command is not installed"
      exit 1
  fi
}

# Exits if the given environment variable key is missing
function assert_env_var() {
  local key="$1"

  if [[ -z "$key" ]]; then
    echo "Error: $key environment variable is not set"
    exit 1
  fi
}

function init() {
  local backup_dir="$1"

  # B2 application key sometimes contain slashes. Since the endpoint
  # is a URI, the key specifically needs to be uri encoded
  local storage_url="b2://${B2_BUCKET_NAME}"

  duplicacy init \
    -erasure-coding 5:2 \
    -repository "$backup_dir" \
    -storage-name "$STORAGE_NAME" \
    "pcb-minecraft" \
    "$storage_url"
}

function backup() {
  # Memo:
  #  -background to force reading secrets from env vars (i.e. non-interactive)
  #  -log to add timestamps and other useful data for logging
  duplicacy backup \
    -storage "$STORAGE_NAME" \
    -e -key public.pem \
    -stats \
    -background \
    -log
}

function verify() {
  # TODO: check whether using -files will hurt my wallet...
  duplicacy check \
    -storage "$STORAGE_NAME" \
    -rewrite \
    -background \
    -log
}

function clean_up() {
  # 0:30 = Remove all backups older than 30 days
  duplicacy prune \
    -storage "$STORAGE_NAME" \
    -keep 0:30 \
    -background \
    -log
}

function send_minecraft_command() {
  local command="$1"

  curl -X POST "${PTERODACTYL_BASE_URL}/api/client/servers/${PTERODACTYL_SERVER_IDENTIFIER}/command" \
    -H "Authorization: Bearer ${PTERODACTYL_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"command\":\"${command}\"}"
}

function enable_world_saving() {
  send_minecraft_command "save-on"
  send_minecraft_command "save-all"
}

function disable_world_saving() {
  send_minecraft_command "save-off"
  send_minecraft_command "save-all"
}

function post_discord_message() {
  local message="$1"
  local color="$2"

  curl -i \
    -H "Accept: application/json" \
    -H "Content-Type:application/json" \
    -X POST --data "{\"content\":\"\",\"tts\":false,\"embeds\":[{\"title\":\"$message\",\"color\":$color,\"fields\":[]}]}" \
    ${DISCORD_WEBHOOK_URL}
}

function notify_failure() {
  local message="$1"
  post_discord_message "❌ $message" "10426906"
}

function notify_success() {
  local message="$1"
  post_discord_message "✔ $message" "2400045"
}

function main() {
  assert_command "duplicacy"

  get_args "$@"
  load_env_file

  if [ -n "$PROXY" ]; then
    eval "duplicacy $PROXY"
    exit 0
  fi

  if [ -n "$BACKUP_DIR" ]; then
    echo "Initializing repository..."
    init "$BACKUP_DIR"
    exit 0
  fi

  local start=$(date +%s)

  # TODO: ping health check service

  # Always re-enable world saving on the server, regardless of
  # success or failure
  trap 'enable_world_saving' EXIT

  disable_world_saving
  sleep 10s # Wait for save to finish

  backup || {
    echo "Backup failed, notifying Discord..."
    notify_failure "[$STORAGE_NAME] Backup failed"
    exit 1
  }

  verify || {
    echo "Backup verification failed, notifying Discord..."
    notify_failure "[$STORAGE_NAME] Backup verification failed"
    exit 1
  }

  clean_up || {
    echo "Backup clean-up failed, notifying Discord..."
    notify_failure "[$STORAGE_NAME] Backup clean-up failed"
    exit 1
  }

  local end=$(date +%s)
  local duration=$((end - start))
  echo "Operation completed in $duration seconds"

  notify_success "[$STORAGE_NAME] Backup completed"

  # Clean up logs older than 60 days
  find /var/log/pcb-backup/ -mindepth 1 -mtime +60 -delete

  exit 0
}

mkdir -p /var/log/pcb-backup
main "$@" >> "/var/log/pcb-backup/$STORAGE_NAME-$(date +'%Y-%m-%d').log"