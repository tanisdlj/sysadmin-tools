#!/bin/bash
# Call backup method, call check mongo. If primary, error
# Call restore method, call check mongo. If primary, no error
# Args management
# usage
# lock file

# Backup location
readonly FULL_PATH="/backup/mongo/full"
readonly INCREMENTAL_PATH='/backup/mongo/incremental'

# LVM where Mongo data is stored
VOLUME_GROUP='mongo_data'
LOGICAL_VOLUME='mongodata'
readonly LVM_PATH="/dev/${VOLUME_GROUP}/${LOGICAL_VOLUME}"
readonly MONGO_DATA='/data'

# LVM to restore the backup
readonly RESTORE_NAME='mongo-restore'
readonly RESTORE_PATH="/dev/${VOLUME_GROUP}/${RESTORE_NAME}"

# LVM Snapshot settings
readonly SNAPSHOT_NAME='mongo-snapshot'
readonly SNAPSHOT_PATH="/dev/${VOLUME_GROUP}/${SNAPSHOT_NAME}"
readonly SNAPSHOT_MNT='/mnt/mongo-backup'
SNAPSHOT_SIZE='100G'

# Mongo oplog incremental backup
readonly INCREMENTAL_JSON="${INCREMENTAL_PATH}/oplog.rs.metadata.json"
readonly INCREMENTAL_BSON="${INCREMENTAL_PATH}/oplog.rs.bson"

# REVIEW oplog file method, where it is placed (should be on backup/?)
readonly LAST_OPLOG_FILE='/opt/mongo_last_oplog.time'

# Restore file, provided as argument
BACKUP_FILE=''

# Selected option between perform backup or restore.
BACKUP=false
RESTORE=false

# Mongo info
MONGO_VERSION=0
MONGO_STORAGE=""

## Booleans
OLD_VERSION=
WIRED_TIGER=
ISMASTER=

NOW=$(date +"%F_%R")
#LASTOP_TIME=""

###################### GENERIC FUNCTIONS ########################

checkMongoVersion () {
  MONGO_VERSION=`mongod --version | grep -v git | cut -d' ' -f 3`
  local VERSIONTMP="${MONGO_VERSION//.}"
  local VERSION="${VERSIONTMP//v}"

  if [ "${VERSION}" -lt "3200" ]; then
    OLD_VERSION=true
  else
    OLD_VERSION=false
  fi
}

checkMongoEngine () {
  MONGO_STORAGE=`mongo --eval "printjson(db.serverStatus().storageEngine)" | grep name | cut -d'"' -f 4`
  if [ "$MONGO_STORAGE" == "wiredTiger" ]; then
    WIRED_TIGER=true
  else
    WIRED_TIGER=false
  fi
}

checkMongoMaster () {
  local mastertmp=`mongo --eval 'printjson(db.runCommand("ismaster"))' | grep ismaster | cut -d' ' -f 3`
  ISMASTER="${mastertmp//,}"
  if $ISMASTER; then
    echo "ERROR: Backups should be taken from a secondary member"
    exit 1
  fi
}

#################### START / STOP MONGO #########################

stopMongo () {
  if $OLD_VERSION && $WIRED_TIGER; then
    service moongod stop
  else
    mongo --eval "printjson(db.fsyncLock())"
  fi
}

startMongo () {
  if $OLD_VERSION && $WIRED_TIGER; then
    service mongod start
  else
    mongo --eval "printjson(db.fsyncUnlock())"
  fi
}

########################### BACKUP ##############################

lastOplogPosition () {
  echo "  Storing last Oplog time"
  LASTOP_TIME=`mongo --eval 'printjson(db.getSiblingDB("local").oplog.rs.find().sort({$natural:-1}).limit(1).next().ts)' | grep Timestamp`
  if [ -z "$LASTOP_TIME" ]; then
    echo "ERROR: Cannot retrieve last Oplog operation time"
    exit 1
  else
    echo "    Stored in ${LAST_OPLOG_FILE}"
    echo "${LASTOP_TIME}" > ${LAST_OPLOG_FILE}
  fi
}

errormsg () {
  echo "  ERROR: $1"
  exit 1
}

######### FULL  #########

createSnapshot () {
  if [ -e $LVM_PATH ]; then
    lvcreate --snapshot --size $SNAPSHOT_SIZE \
      --name $SNAPSHOT_NAME $LVM_PATH || { errormsg 'Snapshot creation failed'; }
    echo "  Snapshot created"
  else
    errormsg "$LVM_PATH not found"
  fi
}

mountSnapshot () {
  echo "  Mounting ${SNAPSHOT_MNT}"
  if [ ! -d "${SNAPSHOT_MNT}" ]; then
    mkdir ${SNAPSHOT_MNT}
  fi

  mount ${SNAPSHOT_PATH} ${SNAPSHOT_MNT}
}

archiveFullBackup () {
  NOW=$(date +"%F_%R")
  local FULL_FILE="${FULL_PATH}/mongoFull.${NOW}.gz"

  echo "  Archiving $FULL_FILE"

#  echo "${LASTOP_TIME}" >> ${SNAPSHOT_MNT}/mongo_last_oplog.time
#  tar -pczf ${FULL_FILE} ${SNAPSHOT_MNT}
  umount ${SNAPSHOT_PATH} > /dev/null 2>&1

  if [ -d "${FULL_PATH}" ]; then
    dd if=${SNAPSHOT_PATH} | gzip > ${FULL_FILE}
  else
    removeSnapshot
    errormsg "Path ${FULL_PATH} not accessible"
  fi
}

removeSnapshot () {
  echo "  Removing ${SNAPSHOT_PATH}"
  umount ${SNAPSHOT_PATH} > /dev/null 2>&1
  lvremove -f ${SNAPSHOT_PATH} || { errormsg "Failed removing snapshot ${SNAPSHOT_PATH}"; }
}


####### INCREMENTAL #######

archiveIncrementalBackup () {
  NOW=$(date +"%F_%R")
  local INCREMENTAL_FILE="${INCREMENTAL_PATH}/oplog.${NOW}.bson"

  local MDBDUMP_OPTIONS="-d local -c oplog.rs -o ${INCREMENTAL_PATH}"
  local LAST_BACKUP_TIME=`cat ${LAST_OPLOG_FILE}`

  mongodump ${MDBDUMP_OPTIONS} --query '{ "ts" : { $gt :  '"${LAST_BACKUP_TIME}"' } }'
  rm ${INCREMENTAL_JSON}
  mv ${INCREMENTAL_BSON} ${INCREMENTAL_FILE}
}


####################### RESTORE ############################

### FULL ###

restoreFullBackup () {
  
  lvcreate --size $SNAPSHOT_SIZE --name $RESTORE_NAME $VOLUME_GROUP
  gzip -d -c ${BACKUP_FILE} | dd of=${RESTORE_PATH}
  mount ${RESTORE_PATH} ${MONGO_DATA}
}


### INCREMENTAL ###

restoreIncrementalBackup () {
  TMP_FOLDER='/tmp/mongorestore/oplog.bson'
  cp ${BACKUP_FILE} ${TMP_FOLDER}
  mongorestore --oplogReplay ${TMP_FOLDER}
}

############# SETUP #################

### BACKUP ###
setupBackup () {
  checkMongoVersion
  checkMongoEngine
  checkMongoMaster

  case "$BACKUP_TYPE" in
    "full" ) setupFullBackup;;
    "incremental" ) setupIncrementalBackup;;
    *) errormsg "Wrong backup type $BACKUP_TYPE";;
  esac
}

setupFullBackup () {
  echo "  Full Backup selected"
#  stopMongo
  createSnapshot
  lastOplogPosition
  archiveFullBackup
  removeSnapshot
#  startMongo
}

setupIncrementalBackup () {
  echo "  Incremental Backup selected"
  stopMongo
  archiveIncrementalBackup
  lastOplogPosition
  startMongo
}

### RESTORE ###

setupRestore () {
  case "$RESTORE_TYPE" in
    "full" ) setupFullRestore;;
    "incremental" ) setupIncrementalRestore;;
    *) errormsg "Wrong backup type $RESTORE_TYPE";;
  esac
}

setupFullRestore () {
  stopMongo
  startMongo
}

setupIncrementalRestore () {
  stopMongo
  startMongo
}

#######################################

checkArgs () {
  if $BACKUP && $RESTORE; then
    errormsg 'Select either backup or restore'
  elif $BACKUP && [ ! -z "$BACKUP_TYPE" ] && [ -z "$BACKUP_FILE" ]; then
    setupBackup
  elif $RESTORE && [ ! -z "$RESTORE_TYPE" ] && [ ! -z "$BACKUP_FILE" ]; then
    setupRestore
  else
    errormsg 'Something went wrong. Check the arguments'
  fi
}

usage () {
  echo "USAGE!"
}

setup () {
  checkArgs
}

# Args handler
if [ $# -eq 0 ] || [[ $(( $# % 2 )) -eq 1 ]]; then
  errormsg 'Wrong number of arguments'
fi


while [ "$#" -gt 0 ]; do
  case $1 in
    -B) BACKUP=true; BACKUP_TYPE=$2; shift 2;;
    -S) SNAPSHOT_SIZE=$2; shift 2;;

    -R) RESTORE=true; RESTORE_TYPE=$2; shift 2;;
    -f) BACKUP_FILE=$2; shift 2;;
    -G) VOLUME_GROUP=$2; shift 2;;
    -V) LOGICAL_VOLUME=$2; shift 2;;
    -h) usage; exit 0;;
    *) echo "ERROR: Invalid option"; usage; exit 2;;
  esac
done

setup
