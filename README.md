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

```
openssl genrsa -aes256 -out private.pem 2048
openssl rsa -in private.pem  -pubout -out public.pem
```


Copy `.env.example` as `.env` and fill in the required secrets

```
cp .env.example .env
```


Initialize the repository

```
./backup.sh -i /my/folder/to/backup
```

> [!NOTE]  
> You will be prompted to set a storage password by Duplicacy. This is only used to encrypt the `config` file (see https://github.com/gilbertchen/duplicacy/wiki/init)

### Backup filter

To update the file include/exclude filter, modify the `filters` file before performing your backup.

See https://github.com/gilbertchen/duplicacy/wiki/Include-Exclude-Patterns for details.

### Backup

```
./backup.sh
```