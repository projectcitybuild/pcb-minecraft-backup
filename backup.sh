#!/bin/bash

set -e

function print_usage() {
  echo "
    Usage: $(basename $0) [OPTIONS]

    Options:
      -d, --directory <path>       Path to the directory to backup
      -t, --target <path>          Directory in the bucket to store the backups
      -h, --help                   Display usage
  "
}

function get_args() {
  while getopts 'd:t:h' OPTION; do
    case "$OPTION" in
      d)
        BACKUP_DIR="$OPTARG"
        ;;
      t)
        TARGET_DIR="$OPTARG"
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
    echo "Error: backup directory must be specified with -d flag"
    exit 1
  fi
  if [[ -z "$TARGET_DIR" ]]; then
      echo "Error: target directory in the bucket must be specified with -t flag"
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

function backup() {
  local backup_dir="$1"
  local s3_endpoint="$2"

  # TODO: log to file system

  duplicity \
    --full-if-older-than 7D \
    --no-encryption \
    --verbosity 8 \
    "${backup_dir}" \
    "${s3_endpoint}"
}

function verify() {
  local backup_dir="$1"
  local s3_endpoint="$2"

  # TODO: log to file system

  duplicity verify \
    --no-encryption \
    "${s3_endpoint}" \
    "${backup_dir}"
}

function clean_up() {
  local s3_endpoint="$1"

  # TODO: log to file system

  duplicity remove-older-than 30D \
    --force \
    "${s3_endpoint}"
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
  assert_command "jq"
  assert_command "duplicity"

  get_args "$@"
  load_env_file

  # B2 application key sometimes contain slashes. Since the endpoint
  # is a URI, the key specifically needs to be uri encoded
  local app_key=$(echo -n "${B2_APPLICATION_KEY}" | jq -sRr @uri)
  local endpoint="b2://${B2_KEY_ID}:${app_key}@${B2_BUCKET_NAME}/${TARGET_DIR}"

  start=$(date +%s)

  # Always re-enable world saving on the server, regardless of
  # success or failure
  trap 'enable_world_saving' EXIT

  disable_world_saving
  sleep 10s # Wait for save to finish

  backup "$BACKUP_DIR" "$endpoint" || {
    echo "Backup failed, notifying Discord..."
    notify_failure "Backup failed"
    exit 1
  }

  verify "$BACKUP_DIR" "$endpoint" || {
    echo "Backup verification failed, notifying Discord..."
    notify_failure "Backup verification failed"
    exit 1
  }

  clean_up "$endpoint" || {
    echo "Backup clean-up failed, notifying Discord..."
    notify_failure "Backup clean-up failed"
    exit 1
  }

  end=$(date +%s)
  duration=$((end - start))
  echo "Operation completed in $duration seconds"
  notify_success "Backup completed"

  exit 0
}

main "$@"