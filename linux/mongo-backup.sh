#!/bin/bash
# Call backup method, call check mongo. If primary, error
# Call restore method, call check mongo. If primary, no error
# Args management
# usage
# lock file

# LVM where Mongo data is stored
LVM_GROUP='mongo_data'
LVM_NAME='mongodata'
LVM_PATH=''

# Backup location
BACKUP_PATH='/backup/mongo'
FULL_PATH=''
INCREMENTAL_PATH=''

# Mongo oplog incremental backup
INCREMENTAL_JSON=''
INCREMENTAL_BSON=''

# LVM Snapshot settings
readonly SNAPSHOT_NAME='mongo-snapshot'
SNAPSHOT_PATH=''
readonly SNAPSHOT_MNT='/mnt/mongo-backup'
SNAPSHOT_SIZE='100G'


# LVM to restore the backup
readonly RESTORE_NAME='mongo-restore'
RESTORE_PATH=''
# Restore file, provided as argument
RESTORE_FILE=''
readonly MONGO_DATA='/data'


# REVIEW oplog file method, where it is placed (should be on backup/?)
LAST_OPLOG_FILE='/opt/mongo_last_oplog.time'


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

  if [ -e ${LAST_OPLOG_FILE} ]; then
    local LAST_BACKUP_TIME=`cat ${LAST_OPLOG_FILE}`
  else
    errormsg "${LAST_OPLOG_FILE} not found or permissions problem"
  fi

  echo "Performing incremental backup"
  mongodump ${MDBDUMP_OPTIONS} --query '{ "ts" : { $gt :  '"${LAST_BACKUP_TIME}"' } }' \
    || { errormsg "Error getting oplog with mongodump ${MDBDUMP_OPTIONS} from ${LAST_BACKUP_TIME}"; }
  rm ${INCREMENTAL_JSON}

  if [ -d "${INCREMENTAL_PATH}" ]; then
    echo "  WARNING: ${INCREMENTAL_PATH} not found. Trying to create"
    mkdir -p ${INCREMENTAL_PATH} || { errormsg "${INCREMENTAL_PATH} dir creation failed. Permissions problem?"; }
  fi

  mv ${INCREMENTAL_BSON} ${INCREMENTAL_FILE} || { errormsg "Error renaming ${INCREMENTAL_BSON} to ${INCREMENTAL_FILE} "; }
}


####################### RESTORE ############################

### FULL ###

restoreFullBackup () {
  
  lvcreate --size $SNAPSHOT_SIZE --name $RESTORE_NAME $LVM_GROUP || { errormsg "${RESTORE_PATH} creation failed"; }

  if [ -e ${RESTORE_FILE} ]; then
    gzip -d -c ${RESTORE_FILE} | dd of=${RESTORE_PATH}

    if [ ! -d ${MONGO_DATA} ]; then
      echo " WARNING: ${MONGO_DATA} not found, trying to create the dir..."
      mkdir -p ${MONGO_DATA}
    fi
    mount ${RESTORE_PATH} ${MONGO_DATA}
  fi
}


### INCREMENTAL ###

restoreIncrementalBackup () {
  TMP_FOLDER='/tmp/mongorestore/oplog.bson'
  cp ${RESTORE_FILE} ${TMP_FOLDER}
  mongorestore --oplogReplay ${TMP_FOLDER}
}

############# SETUP #################

### BACKUP ###
setupBackup () {
  checkMongoVersion
  checkMongoEngine
  checkMongoMaster

  case "$BACKUP_MODE" in
    "full" ) setupFullBackup;;
    "incremental" ) setupIncrementalBackup;;
    *) errormsg "Wrong backup type $BACKUP_MODE";;
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
  case "$RESTORE_MODE" in
    "full" ) setupFullRestore;;
    "incremental" ) setupIncrementalRestore;;
    *) errormsg "Wrong restore type $RESTORE_MODE";;
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
  
  FULL_PATH="${BACKUP_PATH}/full"
  INCREMENTAL_PATH="${BACKUP_PATH}/incremental"
  INCREMENTAL_JSON="${INCREMENTAL_PATH}/oplog.rs.metadata.json"
  INCREMENTAL_BSON="${INCREMENTAL_PATH}/oplog.rs.bson"

  SNAPSHOT_PATH="/dev/${LVM_GROUP}/${SNAPSHOT_NAME}"

  LVM_PATH="/dev/${LVM_GROUP}/${LVM_NAME}"

  RESTORE_PATH="/dev/${LVM_GROUP}/${RESTORE_NAME}"

  if $BACKUP && $RESTORE; then
    errormsg 'Select either backup or restore'
  elif $BACKUP && [ ! -z "$BACKUP_MODE" ] && [ -z "$RESTORE_FILE" ]; then
    setupBackup
  elif $RESTORE && [ ! -z "$RESTORE_MODE" ] && [ ! -z "$RESTORE_FILE" ]; then
    setupRestore
  else
    errormsg 'Something went wrong. Check the arguments'
  fi
}

setup () {
  checkArgs
}

usage () {
  echo "Backup or restore a mongo database, both incremental and full backups."
  echo " Usage:"
  echo "  $(basename $0) -B \$backup_mode [-S \$snapshot_size] [-P \$backup_path] [options] " 
  echo "  $(basename $0) -R \$restore_mode -f \$restore_file [options] "
  echo ""
  echo " -B \$backup_mode   : Perform backup in a backup_mode, either 'full' or 'incremental'"
  echo " -S \$snapshot_size : Specify the max size of the snapshot (optional)"
  echo "                       default: '100G'"
  echo " -P \$backup_path   : Set the directory where the backups will be stored (optional)"
  echo "                       default: '/backup/mongo'"
  echo ""
  echo " -R \$restore_mode  : Restore a type of backup, either 'full' or 'incremental'"
  echo " -f \$restore_file  : Set the file from which the restore will be done"
  echo ""
  echo " Options:"
  echo "  -G \$lvm_group    :  Set the LVM group where mongo data is, or where is going to be (optional)"
  echo "                       default: 'mongo_data'"
  echo "  -V \$lvm_name     :  Set the LVM Volume name where mongo data is, or where is going to be (optional)"
  echo "                       default: 'mongodata'"
  echo "  -t \$last_op_time :  Set the path to the file where the last oplog time is stored, or where is going to be (optional)"
  echo "                       default: '/opt/mongo_last_oplog.time'"

}

errormsg () {
  echo "  ERROR: $1"
  exit 1
}

# Args handler
if [ $# -eq 0 ] || [[ $(( $# % 2 )) -eq 1 ]]; then
  usage
  echo ""
  errormsg 'Wrong number of arguments'
fi

while [ "$#" -gt 0 ]; do
  case $1 in
    -B) BACKUP=true; BACKUP_MODE=$2; shift 2;;
    -S) SNAPSHOT_SIZE=$2; shift 2;;

    -R) RESTORE=true; RESTORE_MODE=$2; shift 2;;
    -f) RESTORE_FILE=$2; shift 2;;

    -P) BACKUP_PATH=$2; shift 2;;

    -G) LVM_GROUP=$2; shift 2;;
    -V) LVM_NAME=$2; shift 2;;
    -t) LAST_OPLOG_FILE=$2; shift 2;;

    -h) usage; exit 0;;
    *) usage; echo ""; echo "ERROR: Invalid option"; exit 2;;
  esac
done


setup
