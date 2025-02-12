#!/bin/bash

###############################################
# Configuration - Start
###############################################

REPOSITORIES=(
  "bash-backup-on-steroids::https://github.com/mimographix/bash-backup-on-steroids.git"
  "ubl-wrapper::https://github.com/uctoplus/ubl-wrapper.git"
#  "directory2::/srv/application/storage"
  # use :: as a separator between file name and directory name
  # you can backup as many repositories as you want
  # dont forget to give user proper rights either by addind SSH key or username/password
)

# Directory have to be present at least for temporary creation of backup even for remote backup
BACKUP_DIR='backups'

PUBLIC_KEY= # GPG mail address or empty

# options for arguments
TEST=false
VERBOSE=false


###############################################
# Configuration - End
###############################################

usage() {
  echo "Usage: git-backup.sh
                  [ --ignore-gpg ]
                  [ --gpg <email@public.key> ]
                  [ -v | --verbose ]
                  [ -t | --test ]
                  [ -h | --help ] "
  exit 2
}

# https://www.shellscript.sh/tips/getopt/index.html
PARSED_ARGUMENTS=$(getopt -a -n alphabet -o vth: --long ignore-gpg,gpg:,verbose,test,help -- "$@")
VALID_ARGUMENTS=$?
if [ "$VALID_ARGUMENTS" != "0" ]; then
  usage
fi

eval set -- "$PARSED_ARGUMENTS"
while :; do
  case "$1" in
  --ignore-gpg)
    PUBLIC_KEY=
    shift
    ;;
  --gpg)
    PUBLIC_KEY="$2"
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

###############################################
# Functions Definitions - Start
###############################################
function log {
  TEXT="[$(date)] ${2:-INFO} $1"
  if [[ $VERBOSE == true ]]; then
    echo "$1"
  fi
  echo "$TEXT" >> "$BACKUP_DIR/last_backup.log"
}

###############################################
# Functions Definitions - End
###############################################


if [ ${#REPOSITORIES[@]} -gt 0 ]; then
  for index in "${REPOSITORIES[@]}"; do
    REPO_NAME="${index%%::*}"
    REPO_URL="${index##*::}"
    log "Start $REPO_NAME Backup"

    BACKUP_TEMP="$BACKUP_DIR/temp"

    log "Cleanup TEMP directory at: $BACKUP_TEMP"
    rm -rf "${BACKUP_TEMP}"

    log "Clone REPO"
    if [[ $TEST == false ]]; then
      git clone ${REPO_URL} ${BACKUP_TEMP}
    fi

    log "Bundle REPO"
    if [[ $TEST == false ]]; then
      git --git-dir "${BACKUP_TEMP}/.git" bundle create "${BACKUP_TEMP}/backup.bundle" --all
    fi

    if [ ! -z $PUBLIC_KEY ]; then
      log "Encrypting DB $db Backup"
      if [[ $TEST == false ]]; then
        gpg --encrypt -r $PUBLIC_KEY "${BACKUP_TEMP}/backup.bundle"

        log "Clean unencrypted version"
        rm "${BACKUP_TEMP}/backup.bundle"

        log "Copy Bundle to Backup folder"
        cp "${BACKUP_TEMP}/backup.bundle.gpg" "${BACKUP_DIR}/${DATE}-${REPO_NAME}.bundle.gpg"
      fi
    else
      log "Copy Bundle to Backup folder"
      DATE=$(date +"%F")

      if [[ $TEST == false ]]; then
        cp "${BACKUP_TEMP}/backup.bundle" "${BACKUP_DIR}/${DATE}-${REPO_NAME}.bundle"
      fi
    fi
    log "End $REPO_NAME Backup"
  done
fi