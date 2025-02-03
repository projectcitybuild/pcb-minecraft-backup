# Backup Script

Bash script that can be run on a cronjob to backup a Minecraft server.

## Requirements

* Linux
* Server running via Pterodactyl Panel
* Discord webhook (for notifications)
* Duplicacy installed

## Usage

### Initial Setup

Generate an asymmetric key pair for encryption

```bash
openssl genrsa -aes256 -out private.pem 2048
openssl rsa -in private.pem  -pubout -out public.pem
```


Copy `.env.example` as `.env` and fill in the required secrets

```bash
cp .env.example .env
```


Initialize the repository

```bash
./backup.sh -i /my/folder/to/backup
```

### Backup filter

To update the file include/exclude filter, modify the `filters` file before performing your backup.

See https://github.com/gilbertchen/duplicacy/wiki/Include-Exclude-Patterns for details.

To test what will get included/excluded, perform a backup as a dry-run.

```bash
# Print everything included/excluded
./backup.sh -d

# Print only what will be excluded
./backup.sh -d | grep 'PATTERN_EXCLUDE'

# Print only what will be included
./backup.sh -d | grep 'PATTERN_INCLUDE'
```

### Backup

```bash
./backup.sh
```

To automate this with a cronjob:

```
0 0 * * * cd /your/path/pcb-minecraft-backup && /bin/bash ./backup.sh
```

> [!IMPORTANT]  
> The `cd` is required because the script assumes it is being run from the git repo directory