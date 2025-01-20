#!/bin/bash

###############################################
# Configuration - Start
###############################################

# Directory have to be present at least for temporary creation of backup even for remote backup
BACKUP_DIR="/mnt/backups"

SRC_CODES=(
  "directory1::/srv/application/www"
  "directory2::/srv/application/storage"
  # use :: as a separator between file name and directory name
  # you can backup as many directories as you want
)

PUBLIC_KEY= # GPG mail address or empty

BACKUP_MODE='local-only' ## Available option ( 'local-only' | 'remote-only' | 'local-remote' )

REMOTE_HOST="user@host"
REMOTE_PORT="22"
REMOTE_DESTINATION="~/backups"

# keeps one of each locally on machine
KEEP_ONE_COPY_ON_LOCAL=true

## Timing
BACKUP_DAILY=true # if set to false backup will not work
BACKUP_RETENTION_DAILY=6
# make incremental backups
BACKUP_DAILY_INCREMENTAL=true

BACKUP_WEEKLY=true # if set to false backup will not work
BACKUP_RETENTION_WEEKLY=3

BACKUP_MONTHLY=true # if set to false backup will not work
BACKUP_RETENTION_MONTHLY=2

## Backup Database
MYSQL_HOST="127.0.0.1"
MYSQL_PORT="3306"
MYSQL_USER="db-user"
MYSQL_PASSWORD="db-password"
MYSQL_BIN=/usr/bin/mysql
MYSQLDUMP_BIN=/usr/bin/mysqldump

# in case you want ssl just replace --skip-ssl for empty string
# nev version of mariadbmysqldump has it as default.
MYSQLDUMP_SSL="--skip-ssl"

# options for arguments
MANUAL=false
TEST=false
VERBOSE=false

###############################################
# Configuration - End
###############################################

usage() {
  echo "Usage: backup.sh  [ --manual ( Creates one manual backup ) ]
                  [ --ignore-database ]
                  [ --ignore-storage ]
                  [ --ignore-gpg ]
                  [ --gpg <email@public.key> ]
                  [ -m | --mode <'local-only' | 'remote-only' | 'local-remote'> ]
                  [ -v | --verbose ]
                  [ -t | --test ]
                  [ -h | --help ] "
  exit 2
}

# https://www.shellscript.sh/tips/getopt/index.html
PARSED_ARGUMENTS=$(getopt -a -n alphabet -o vthm: --long manual,ignore-database,ignore-storage,ignore-gpg,gpg:mode:,verbose,test,help -- "$@")
VALID_ARGUMENTS=$?
if [ "$VALID_ARGUMENTS" != "0" ]; then
  usage
fi

eval set -- "$PARSED_ARGUMENTS"
while :; do
  case "$1" in
  --manual)
    MANUAL=true
    echo "########################################################################"
    echo "# MANUAL MANUAL MANUAL MANUAL MANUAL MANUAL MANUAL MANUAL MANUAL MANUAL"
    echo "########################################################################"
    echo ""
    shift
    ;;
  --ignore-database)
    MYSQL_HOST=
    shift
    ;;
  --ignore-storage)
    SRC_CODES=()
    shift
    ;;
  --ignore-gpg)
    PUBLIC_KEY=
    shift
    ;;
  --gpg)
    PUBLIC_KEY="$2"
    shift
    ;;
  -m | --mode)
    BACKUP_MODE="$2"
    shift
    ;;
  -v | --verbose)
    VERBOSE=true
    shift
    ;;
  -t | --test)
    echo "########################################################################"
    echo "# TEST TEST TEST TEST TEST TEST TEST TEST TEST TEST TEST TEST TEST TEST"
    echo "########################################################################"
    echo ""
    TEST=true
    VERBOSE=true
    databases='db1
db2
db3'
    shift
    ;;
  -h | --help) usage ;;
  # -- means the end of the arguments; drop this, and break out of the while loop
  --)
    shift
    break
    ;;
  # If invalid options were passed, then getopt should have reported an error,
  # which we checked as VALID_ARGUMENTS when getopt was called...
  *)
    echo "Unexpected option: $1 - this should not happen."
    usage
    ;;
  esac
done

# kill on error
set -e

# Guessing time
MONTH=$(date +%d)
DAYWEEK=$(date +%u)

# Incremental uses weekly and monthly backups as full backups
if [[ ($BACKUP_DAILY == true) && ($BACKUP_DAILY_INCREMENTAL == true) ]]; then
  if [[ ($BACKUP_MONTHLY == false) && ($BACKUP_WEEKLY == false) ]]; then
    # This if failsafe in case of missconfiguration
    BACKUP_WEEKLY=true
    BACKUP_RETENTION_WEEKLY=1
  fi

  if [[ ($BACKUP_RETENTION_DAILY -lt 6) ]]; then
    BACKUP_RETENTION_DAILY=6
  fi
fi

# https://stackoverflow.com/a/24777667
if [[ (${MONTH#0} -eq 1) && ($BACKUP_MONTHLY == true) ]]; then
  FN='monthly'
elif [[ ($DAYWEEK -eq 7) && ($BACKUP_WEEKLY == true) ]]; then
  FN='weekly'
elif [[ ($DAYWEEK -lt 7) && ($BACKUP_DAILY == true) ]]; then
  FN='daily'
fi

DIR_NAME=$(date +"%F")-$FN

# this will set variables just for testing
if [[ $TEST == true ]]; then
  BACKUP_DIR="."
fi

# create only one backup of latest state e.g. before upgrade
if [[ $MANUAL == true ]]; then
  DIR_NAME="manual"
fi

ACTIVE_BACKUP_DIR="${BACKUP_DIR}/${DIR_NAME}"
if [[ (FN == 'daily') && ($BACKUP_DAILY_INCREMENTAL == true) && $MANUAL == false ]]; then
  ACTIVE_BACKUP_DIR="${ACTIVE_BACKUP_DIR}_i"
fi

###############################################
# Functions Definitions - Start
###############################################
function log {
  TEXT="[$(date)] ${2:-INFO} $1"
  if [[ $VERBOSE == true ]]; then
    echo "$1"
  fi
  echo "$TEXT" >>"$BACKUP_DIR/last_backup.log"
}

function generateBackup {
  BACKUP_TEMP="$BACKUP_DIR/temp"

  log "Cleanup TEMP directory at: $BACKUP_TEMP"
  rm -rf "$BACKUP_TEMP"

  log "Recreate TEMP directory at: $BACKUP_TEMP"
  mkdir -p "$BACKUP_TEMP/mysql"

  if [[ ! -z "$MYSQL_HOST" ]]; then
    if [[ $TEST == false ]]; then
      databases=$($MYSQL_BIN -h ${MYSQL_HOST} -P ${MYSQL_PORT} --user=${MYSQL_USER} -p${MYSQL_PASSWORD} -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema)")
    fi

    for db in $databases; do
      log "Start DB $db Backup"
      if [[ $TEST == false ]]; then
        $MYSQLDUMP_BIN --force --opt -h ${MYSQL_HOST} -P ${MYSQL_PORT} --user=${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQLDUMP_SSL} --databases $db | gzip >"$BACKUP_TEMP/mysql/$db.sql.gz"
      fi

      if [ ! -z $PUBLIC_KEY ]; then
        log "Encrypting DB $db Backup"
        if [[ $TEST == false ]]; then
          gpg --encrypt -r $PUBLIC_KEY "$BACKUP_TEMP/mysql/$db.sql.gz"
          log "Clean unencrypted version"
          rm "$BACKUP_TEMP/mysql/$db.sql.gz"
        fi
      fi

      log "End DB $db Backup"
    done
  fi

  if [ ${#SRC_CODES[@]} -gt 0 ]; then
    for index in "${SRC_CODES[@]}"; do
      KEY="${index%%::*}"
      VALUE="${index##*::}"
      log "Start $VALUE Backup"

      TMP_FILE_NAME="${BACKUP_TEMP}/${KEY}.tar"
      if [[ ($FN == 'daily') && ($BACKUP_DAILY_INCREMENTAL == true) && ($MANUAL == false) ]]; then
        TMP_FILE_NAME="${BACKUP_TEMP}/${KEY}.${DAYWEEK}.tar"
      fi

      if [[ $MANUAL == true ]]; then
        KEY="manual"
      fi

      if [[ $TEST == false ]]; then
        if [[ ($FN == 'weekly') || ($FN == 'monthly') || ($BACKUP_DAILY_INCREMENTAL == false) || ($BACKUP_DAILY_INCREMENTAL == true && $MANUAL == true) ]]; then
          if [ -f "${BACKUP_DIR}/${KEY}.snar" ]; then
            rm -r "${BACKUP_DIR}/${KEY}.snar"
          fi
        fi

        # https://newbedev.com/fastest-way-combine-many-files-into-one-tar-czf-is-too-slow
        if [[ $VERBOSE == true ]]; then
          tar -cv --listed-incremental="${BACKUP_DIR}/${KEY}.snar" --file ${TMP_FILE_NAME} ${VALUE}
        else
          tar -c --listed-incremental="${BACKUP_DIR}/${KEY}.snar" --file ${TMP_FILE_NAME} ${VALUE}
        fi
      fi

      if [ ! -z $PUBLIC_KEY ]; then
        log "Encrypting $VALUE Backup"
        if [[ $TEST == false ]]; then
          gpg --encrypt -r ${PUBLIC_KEY} ${TMP_FILE_NAME}
          log "Clean unencrypted version"
          rm $TMP_FILE_NAME
        fi
      fi

      log "End $VALUE Backup"
    done
  fi

  log "Move to its place: $ACTIVE_BACKUP_DIR"
  if [ $TEST == false ] || [ $MANUAL == false ]; then
    mv $BACKUP_TEMP $ACTIVE_BACKUP_DIR
  fi

  log "Move log"
  if [[ $TEST == false ]]; then
    mv "${BACKUP_DIR}/last_backup.log" "${ACTIVE_BACKUP_DIR}/backup.log"
    cp "${BACKUP_DIR}/${KEY}.snar" "${ACTIVE_BACKUP_DIR}/${KEY}.snar"
  fi
}

function local_only {
  generateBackup

  log "Cleanup old"
  cd $BACKUP_DIR/
  if [[ $TEST == false ]]; then
    ls -t $BACKUP_DIR | grep daily | sed -e 1,"$BACKUP_RETENTION_DAILY"d | xargs -d '\n' rm -rf >/dev/null 2>&1
    ls -t $BACKUP_DIR | grep weekly | sed -e 1,"$BACKUP_RETENTION_WEEKLY"d | xargs -d '\n' rm -rf >/dev/null 2>&1
    ls -t $BACKUP_DIR | grep monthly | sed -e 1,"$BACKUP_RETENTION_MONTHLY"d | xargs -d '\n' rm -rf >/dev/null 2>&1
  else
    ls -t $BACKUP_DIR | grep daily | sed -e 1,"$BACKUP_RETENTION_DAILY"d
    ls -t $BACKUP_DIR | grep weekly | sed -e 1,"$BACKUP_RETENTION_WEEKLY"d
    ls -t $BACKUP_DIR | grep monthly | sed -e 1,"$BACKUP_RETENTION_MONTHLY"d
  fi
}

function local_remote {
  local_only
  if [[ $TEST == false ]]; then
    rsync -avh --delete --port=$REMOTE_PORT $BACKUP_DIR/ $REMOTE_HOST:$REMOTE_DESTINATION
  fi
}

function remote_only {
  generateBackup

  log "Transfer to remote"
  if [[ $TEST == false ]]; then
    scp -rq -P$REMOTE_PORT $ACTIVE_BACKUP_DIR $REMOTE_HOST:$REMOTE_DESTINATION
  fi

  log "Cleanup old form remote"
  if [[ $TEST == false ]]; then
    ssh -t -t $REMOTE_HOST "cd $REMOTE_DESTINATION ; ls -t | grep daily | sed -e 1,"$BACKUP_RETENTION_DAILY"d | xargs -d '\n' rm -rf > /dev/null 2>&1"
    ssh -t -t $REMOTE_HOST "cd $REMOTE_DESTINATION ; ls -t | grep weekly | sed -e 1,"$BACKUP_RETENTION_WEEKLY"d | xargs -d '\n' rm -rf > /dev/null 2>&1"
    ssh -t -t $REMOTE_HOST "cd $REMOTE_DESTINATION ; ls -t | grep monthly | sed -e 1,"$BACKUP_RETENTION_MONTHLY"d | xargs -d '\n' rm -rf > /dev/null 2>&1"
  else
    ssh -t -t $REMOTE_HOST "cd $REMOTE_DESTINATION ; ls -t | grep daily | sed -e 1,"$BACKUP_RETENTION_DAILY"d"
    ssh -t -t $REMOTE_HOST "cd $REMOTE_DESTINATION ; ls -t | grep weekly | sed -e 1,"$BACKUP_RETENTION_WEEKLY"d"
    ssh -t -t $REMOTE_HOST "cd $REMOTE_DESTINATION ; ls -t | grep monthly | sed -e 1,"$BACKUP_RETENTION_MONTHLY"d"
  fi

  log "Cleanup old on local"
  cd $BACKUP_DIR/
  if [ $KEEP_ONE_COPY_ON_LOCAL == true ]; then
    log "Keeping one copy of each locally"
    if [[ $TEST == false ]]; then
      ls -t | grep daily | sed -e 1,1d | xargs -d '\n' rm -rf >/dev/null 2>&1
      ls -t | grep weekly | sed -e 1,1d | xargs -d '\n' rm -rf >/dev/null 2>&1
      ls -t | grep monthly | sed -e 1,1d | xargs -d '\n' rm -rf >/dev/null 2>&1
    else
      ls -t | grep daily | sed -e 1,1d
      ls -t | grep weekly | sed -e 1,1d
      ls -t | grep monthly | sed -e 1,1d
    fi
  else
    if [[ $TEST == false ]]; then
      rm -rf ./* >/dev/null 2>&1
    fi
  fi
}
###############################################
# Functions Definitions - End
###############################################

log "########################################################################"
log "# Start backup with MODE: $BACKUP_MODE"
log "########################################################################"
if [[ ($BACKUP_DAILY == true) && (! -z "$BACKUP_RETENTION_DAILY") && ($BACKUP_RETENTION_DAILY -ne 0) && ($FN == "daily") ]]; then
  if [ $BACKUP_MODE == "local-remote" ]; then
    local_remote
  elif [ $BACKUP_MODE == "local-only" ]; then
    local_only
  elif [ $BACKUP_MODE == "remote-only" ]; then
    remote_only
  fi
fi

if [[ ($BACKUP_WEEKLY == true) && (! -z "$BACKUP_RETENTION_WEEKLY") && ($BACKUP_RETENTION_WEEKLY -ne 0) && ($FN == "weekly") ]]; then
  if [ $BACKUP_MODE == "local-remote" ]; then
    local_remote
  elif [ $BACKUP_MODE == "local-only" ]; then
    local_only
  elif [ $BACKUP_MODE == "remote-only" ]; then
    remote_only
  fi
fi

if [[ ($BACKUP_MONTHLY == true) && (! -z "$BACKUP_RETENTION_MONTHLY") && ($BACKUP_RETENTION_MONTHLY -ne 0) && ($FN == "monthly") ]]; then
  if [ $BACKUP_MODE == "local-remote" ]; then
    local_remote
  elif [ $BACKUP_MODE == "local-only" ]; then
    local_only
  elif [ $BACKUP_MODE == "remote-only" ]; then
    remote_only
  fi
fi

log "End backup"
