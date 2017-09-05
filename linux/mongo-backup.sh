#!/bin/bash
# Call backup method, call check mongo. If primary, error
# Call restore method, call check mongo. If primary, no error
# Args management
# usage
# lock file

# LVM where Mongo data is stored
readonly VOLUME_GROUP='mongo_data'
readonly LOGICAL_VOLUME='mongodata'
readonly LVM_PATH="/dev/${VOLUME_GROUP}/${LOGICAL_VOLUME}"
readonly MONGO_DATA='/data'

# LVM to restore the backup
readonly RESTORE_NAME='mongo-restore'
readonly RESTORE_PATH="/dev/${VOLUME_GROUP}/${RESTORE_NAME}"

# LVM Snapshot settings
readonly SNAPSHOT_SIZE='10G'
readonly SNAPSHOT_NAME='mongo-snapshot'
readonly SNAPSHOT_PATH="/dev/${VOLUME_GROUP}/${SNAPSHOT_NAME}"
readonly SNAPSHOT_MNT='/mnt/mongo-backup'

# Backup location
readonly FULL_PATH="/backup/mongo/full"
readonly INCREMENTAL_PATH='/backup/mongo/incremental'

# Mongo oplog incremental backup
readonly INCREMENTAL_JSON="${INCREMENTAL_PATH}/oplog.rs.metadata.json"
readonly INCREMENTAL_BSON="${INCREMENTAL_PATH}/oplog.rs.bson"

# REVIEW oplog file method, where it is placed (should be on backup/?)
readonly LAST_OPLOG_FILE='/opt/mongo_last_oplog.time'

# Restore file, provided as argument
BACKUP_FILE=''

# Mongo info
MONGO_VERSION=0
MONGO_STORAGE=""

## Booleans
OLD_VERSION=
WIRED_TIGER=
ISMASTER=

#LASTOP_TIME=""

checkMongoVersion () {
  MONGO_VERSION=`mongod --version | grep -v git | cut -d' ' -f 3`
  local VERSIONTMP="${MONGO_VERSION//.}"
  local VERSION="${VERSIONTMP//v}"

  if [ "${VERSION}" -gt "3200" ]; then
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

createSnapshot () {
  lvcreate --snapshot --size $SNAPSHOT_SIZE --name $SNAPSHOT_NAME $LVM_PATH

  if $?; then
    echo "Snapshot created"
  else
    echo "ERROR: Snapshot failed"
    exit 1
  fi
}

mountSnapshot () {
  if [ ! -d "${SNAPSHOT_MNT}" ]
    mkdir ${SNAPSHOT_MNT}
  fi

  mount ${SNAPSHOT_PATH} ${SNAPSHOT_MNT}
}

lastOplogPosition () {
  LASTOP_TIME=`mongo --eval 'printjson(db.getSiblingDB("local").oplog.rs.find().sort({$natural:-1}).limit(1).next().ts)' | grep Timestamp`
  if [ -z "$LASTOP_TIME" ]; then
    echo "ERROR: Cannot retrieve last Oplog operation time"
    exit 1
  else
    echo "${LASTOP_TIME}" >> ${LAST_OPLOG_FILE}
  fi
}

archiveFullBackup () {
  local now=$(date +"%Y_%m_%d")
  local FULL_FILE="${FULL_PATH}/mongoFull_${now}.gz"

#  echo "${LASTOP_TIME}" >> ${SNAPSHOT_MNT}/mongo_last_oplog.time
#  tar -pczf ${FULL_FILE} ${SNAPSHOT_MNT}
  umount ${SNAPSHOT_PATH} > /dev/null 2>&1
  dd if=${SNAPSHOT_PATH} | gzip ${FULL_PATH}/mongoFull_${now}.gz
}

removeSnapshot () {
  umount ${SNAPSHOT_PATH} > /dev/null 2>&1
  lvremove -f ${SNAPSHOT_PATH}
}

archiveIncrementalBackup () {
  local now=$(date +"%m_%d_%Y")
  local INCREMENTAL_FILE="${INCREMENTAL_PATH}/oplog.${now}.bson"

  local MDBDUMP_OPTIONS="-d local -c oplog.rs -o ${INCREMENTAL_PATH}"
  local LAST_BACKUP_TIME=`cat ${LAST_OPLOG_FILE}`

  mongodump ${MDBDUMP_OPTIONS} --query '{ "ts" : { $gt :  '"${LAST_BACKUP_TIME}"' } }'
  rm ${INCREMENTAL_JSON}
  mv ${INCREMENTAL_BSON} ${INCREMENTAL_FILE}
}

restoreFullBackup () {
  BACKUP_FILE=$1
  lvcreate --size $SNAPSHOT_SIZE --name $RESTORE_NAME $VOLUME_GROUP
  gzip -d -c ${BACKUP_FILE} | dd of=${RESTORE_PATH}
  mount ${RESTORE_PATH} ${MONGO_DATA}
}

restoreIncrementalBackup () {
  BACKUP_FILE=$1
  TMP_FOLDER='/tmp/mongorestore/oplog.bson'
  cp ${BACKUP_FILE} ${TMP_FOLDER}
  mongorestore --oplogReplay ${TMP_FOLDER}
}

setupFullBackup () {
  checkMongoMaster
#  stopMongo
  createSnapshot
  lastOplogPosition
  mountSnapshot
  archiveFullBackup
#  startMongo
}

setupIncrementalBackup () {
  checkMongoMaster
  stopMongo
  archiveIncrementalBackup
  lastOplogPosition
  startMongo
}

restoreFullBackup () {
  stopMongo
  startMongo
}

restoreIncrementalBackup () {

}

setup () {
  checkMongoVersion
  checkMongoEngine
}

#Args handler

setup
