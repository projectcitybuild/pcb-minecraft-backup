#!/bin/bash

set -e

LOG_DIR="/var/log/pcb-backup"
STORAGE_NAME="PCB_B2"

function print_usage() {
  echo "
    Usage: $(basename $0) [OPTIONS]

    Options:
      -i  --init        Initializes the Duplicacy storage, passing in the path to the directory to be backed up

      -n  --name        Snapshot id to uniquely identify the backup repo. Required because multiple repos can
                        be attached to the same storage

      -d  --dry-run     Only prints out what would be backed-up

      -h, --help        Display command usage info
  "
}

function get_args() {
  DRY_RUN=false

  while getopts 'i:n:dh' OPTION; do
    case "$OPTION" in
      i)
        BACKUP_DIR="$OPTARG"
        ;;
      n)
        SNAPSHOT_ID="$OPTARG"
        ;;
      d)
        DRY_RUN=true
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

  if [[ -n "$BACKUP_DIR" && -z "$SNAPSHOT_ID" ]]; then
    echo "Error: snapshot id must be specified with the -n option"
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
  assert_env_var "DUPLICACY_CONFIG_PASSWORD"
  assert_env_var "PTERODACTYL_TOKEN"
  assert_env_var "PTERODACTYL_SERVER_IDENTIFIER"
  assert_env_var "PTERODACTYL_BASE_URL"
  assert_env_var "DISCORD_WEBHOOK_URL"
  assert_env_var "HEALTHCHECK_URL"

  # Export key to env to avoid interactive authentication when
  # initializing the repo.
  #
  # Normally the key is DUPLICACY_B2_ID, but for non-default storage
  # it becomes DUPLICACY_<STORAGENAME>_B2_ID in all uppercase
  # See https://github.com/gilbertchen/duplicacy/wiki/Managing-Passwords
  local name="${STORAGE_NAME^^}"
  eval "export DUPLICACY_${name}_B2_ID=$B2_KEY_ID"
  eval "export DUPLICACY_${name}_B2_KEY=$B2_APPLICATION_KEY"

  # Duplicacy encrypts the `config` file with a different password
  export "DUPLICACY_${name}_PASSWORD=$DUPLICACY_CONFIG_PASSWORD"

  echo "Exported DUPLICACY_${name}_B2_ID"
  echo "Exported DUPLICACY_${name}_B2_KEY"
  echo "Exported DUPLICACY_${name}_PASSWORD"
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

function sync_file_filter() {
  echo "Updating the file filter..."
  cp filters .duplicacy/filters
}

function init() {
  local backup_dir="$1"

  # B2 application key sometimes contain slashes. Since the endpoint
  # is a URI, the key specifically needs to be uri encoded
  local storage_url="b2://${B2_BUCKET_NAME}"

  duplicacy -log -background init \
    -encrypt -key public.pem \
    -erasure-coding 5:2 \
    -repository "$backup_dir" \
    -storage-name "$STORAGE_NAME" \
    "$SNAPSHOT_ID" \
    "$storage_url"
}

function backup() {
  # Memo:
  #  -background to force reading secrets from env vars (i.e. non-interactive)
  #  -log to add timestamps and other useful data for logging
  #  -threads is for uploading chunks (i.e. upload speed)
  duplicacy -log -background backup \
      -storage "$STORAGE_NAME" \
      -stats \
      -threads 16
}

function verify() {
  # TODO: check whether using -files will hurt my wallet...
  duplicacy -log -background check \
    -storage "$STORAGE_NAME" \
    -rewrite
}

function clean_up() {
  # 0:30 = Remove all backups older than 30 days
  duplicacy -log -background prune \
    -storage "$STORAGE_NAME" \
    -keep 0:30
}

function backup_dry_run() {
  echo "Running in dry-run mode. Files will not be uploaded..."

  #  -enum-only prints out included/excluded files for filter testing
  #  -debug is required to do a -enum-only
  duplicacy -debug -log backup -enum-only
}

function send_minecraft_command() {
  local command="$1"

  curl -X POST "${PTERODACTYL_BASE_URL}/api/client/servers/${PTERODACTYL_SERVER_IDENTIFIER}/command" \
    -H "Authorization: Bearer ${PTERODACTYL_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"command\":\"${command}\"}"
}

function enable_world_saving() {
  echo "Enabling world saving..."

  send_minecraft_command "save-on"
  send_minecraft_command "save-all"
}

function disable_world_saving() {
  echo "Disabling world saving..."

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

function ping_healthcheck() {
  echo "Pinging healthcheck service..."

  # -m 10 = Maximum time allowed for a HTTP request to take (per request - reset on each retry)
  curl -m 10 --retry 5 "${HEALTHCHECK_URL}"
}

function main() {
  mkdir -p "$LOG_DIR"

  {
    assert_command "duplicacy"

    get_args "$@"
    load_env_file

    if [ -n "$BACKUP_DIR" ]; then
      echo "Initializing repository..."
      init "$BACKUP_DIR"
      exit 0
    fi

    sync_file_filter

    if [ "$DRY_RUN" = true ]; then
      backup_dry_run
      exit 0
    fi

    # Inform the healthcheck service that the (backup) script ran.
    #
    # We don't care about the result of the backup here.
    # Failure to ping the healthcheck reports to us that there's a
    # problem with the cronjob or the service running this script.
    ping_healthcheck || {
      echo "Warning: Failed to ping healthcheck service..."
      notify_failure "[$STORAGE_NAME] Warning: Failed to ping healthcheck service"
    }

    echo "Beginning backup..."
    local start=$(date +%s)

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
    find "$LOG_DIR" -mindepth 1 -mtime +60 -delete

    exit 0
  } 2>&1 | tee -a "$LOG_DIR/$STORAGE_NAME-$(date +'%Y-%m-%d').log"
  # Pipe to tee so that it logs but also outputs to console
  # Memo: -a = append instead of overwrite
}

main "$@"