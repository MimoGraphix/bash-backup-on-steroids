# Bash backups on steroids 💪

This _"simple"_ script allows you to backup your application files and databases with possibility to move all backups to remote server.

## Usage
```text
Usage: backup.sh    [ --manual ( Creates one manual backup ) ]
                    [ --ignore-database ]
                    [ --ignore-storage ]
                    [ --gpg <email@public.key> ]
                    [ -m | --mode <'local-only' | 'remote-only' | 'local-remote'> ]
                    [ -v | --verbose ]
                    [ -t | --test ]
                    [ -h | --help ]
```


## Configuration

### Multiple backup modes
- `local-only` - created backup only locally on the machine. _NOTE:_ Be careful this is very storage space consuming.
- `remote-only` - move locally created backups to the remote machine. _NOTE:_ Additional configuration `KEEP_ONE_COPY_ON_LOCAL` allows you to keep one of each backups locally on machine. 
- `local-remote` - rsync backup files between local and remote server

```shell
BACKUP_MODE='local-only' ## Available option ( 'local-only' | 'remote-only' | 'local-remote' )
```


### List of directories to backup
You can backup multiple directories by putting them into array. Use `::` as a separator between tar file name and directory
```shell
SRC_CODES=(
  "directory1::/srv/application/www"
  "directory2::/srv/application/storage"
)
```

### Protect your backups
You can protect your backups with Public GPG key which allows you to safely moves files between servers and decrypt files only on computer with Private key pair 
```shell
PUBLIC_KEY="email@public.key"
```

### Timing and retention
You can set how many copies you want to keep and which types of backups you want to have.
```shell
BACKUP_DAILY=true   # if set to false backup will not work
BACKUP_RETENTION_DAILY=6

BACKUP_WEEKLY=true  # if set to false backup will not work
BACKUP_RETENTION_WEEKLY=3

BACKUP_MONTHLY=true # if set to false backup will not work
BACKUP_RETENTION_MONTHLY=2
```

### Backup Database
Set your MySQL/MariaBD settings, backup will dump all databases separately except of default mysql databases.
```shell
MYSQL_HOST="127.0.0.1"
MYSQL_USER="db-user"
MYSQL_PASSWORD="db-password"
```

### Remote server setup
```shell
REMOTE_HOST="user@host"
REMOTE_DESTINATION="~/backups"
KEEP_ONE_COPY_ON_LOCAL=true # keeps one of each locally on machine
```

