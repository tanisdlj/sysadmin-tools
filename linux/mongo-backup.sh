#!/bin/bash
# Backup and restore a mongo database using LVM Snapshots.
# Writen by Diego Lucas Jimenez, 2017, for Projectplace.
# ToDo: Restore => check master; check disk (of)

readonly SCRIPT_VERSION='0.9.1'

# LVM where Mongo data is stored
LVM_GROUP='mongo_data'
LVM_NAME='mongodata'
LVM_PATH=''

# Backup location
BACKUP_USER=''
BACKUP_SERVER=''
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
VOLUME_SIZE='100G'
FS_TYPE='ext4'


# LVM to restore the backup
readonly RESTORE_NAME='mongo-restore'
RESTORE_PATH=''
# Restore file, provided as argument
RESTORE_FILE=''
MONGODB_DATA='/data'


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

NOW=$(date +"%F_%H%M")
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
  if [ ! $ISMASTER ]; then
#    echo "ERROR: Backups should be taken from a secondary member"
    echo "ERROR: Not Master"
    exit 1
  fi
}

#################### START / STOP MONGO #########################

stopMongo () {
  if $OLD_VERSION && $WIRED_TIGER; then
    echo "  Stopping mongo..."
    service mongod stop || { errormsg 'Service mongod stop failed'; }
  else
    echo "  Locking mongo writes and flushing operations..."
    mongo --eval "printjson(db.fsyncLock())" || { errormsg 'Failed fsyncLock'; }
  fi
}

startMongo () {
  if $OLD_VERSION && $WIRED_TIGER; then
    echo "  Starting mongo..."
    service mongod start || { errormsg 'Service mongod start failed'; }
  else
    echo "  Unlocking mongo writes..."
    mongo --eval "printjson(db.fsyncUnlock())" || { errormsg 'Failed fsyncUnlock'; }
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
# Oplog seems to use an odd time
#    sed -i 's/,/000,/' ${LAST_OPLOG_FILE}
  fi
}

######### FULL  #########

createSnapshot () {
  echo "  Taking LVM snapshot"

  if [ -e $LVM_PATH ]; then
    /sbin/lvcreate --snapshot --size $VOLUME_SIZE \
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

  /bin/mount ${SNAPSHOT_PATH} ${SNAPSHOT_MNT}
}

archiveFullBackup () {
  NOW=$(date +"%F_%H%M")
  local FULL_FILE="${FULL_PATH}/mongoFull.${NOW}.gz"

  echo "  Archiving ${BACKUP_USER}@${BACKUP_SERVER}:${FULL_FILE}"

#  echo "${LASTOP_TIME}" >> ${SNAPSHOT_MNT}/mongo_last_oplog.time
#  tar -pczf ${FULL_FILE} ${SNAPSHOT_MNT}
  /bin/umount ${SNAPSHOT_PATH} > /dev/null 2>&1

  if ssh ucsbackup@satvmlst01.sa.projectplace.com "ls ${FULL_PATH}" ; then
    dd if=${SNAPSHOT_PATH} | gzip -1 - | ssh ${BACKUP_USER}@${BACKUP_SERVER} dd of=${FULL_FILE} \
     || { removeSnapshot; errormsg "Failed archiving snapshot ${SNAPSHOT_PATH} in ${FULL_FILE}"; }
  else
    removeSnapshot
    errormsg "Path ${BACKUP_USER}@${BACKUP_SERVER}:${FULL_PATH} not accessible"
  fi
}

removeSnapshot () {
  echo "  Removing ${SNAPSHOT_PATH}"
  /bin/umount ${SNAPSHOT_PATH} > /dev/null 2>&1
  /sbin/lvremove -f ${SNAPSHOT_PATH} || { errormsg "Failed removing snapshot ${SNAPSHOT_PATH}"; }
}


####### INCREMENTAL #######

archiveIncrementalBackup () {
  NOW=$(date +"%F_%H%M")

  local INCREMENTAL_FILE="${INCREMENTAL_PATH}/oplog.${NOW}.bson"
  local MDBDUMP_OPTIONS="-d local -c oplog.rs -o ${INCREMENTAL_PATH}"

  if [ -e ${LAST_OPLOG_FILE} ]; then
    local LAST_BACKUP_TIME=`cat ${LAST_OPLOG_FILE}`
  else
    errormsg "${LAST_OPLOG_FILE} not found or permissions problem"
  fi

  echo "  Performing incremental backup"
# Secondary
#  mongo --eval "rs.slaveOk()" --shell
  mongodump ${MDBDUMP_OPTIONS} --query '{ "ts" : { $gt :  '"${LAST_BACKUP_TIME}"' } }' \
    || { errormsg "Error getting oplog with mongodump ${MDBDUMP_OPTIONS} from ${LAST_BACKUP_TIME}"; }

  if [ ! -d "${INCREMENTAL_PATH}/local" ]; then
    errormsg "${INCREMENTAL_PATH}/local not found. Permissions problem or wrong path?"
  fi

  rm ${INCREMENTAL_JSON}
  mv ${INCREMENTAL_BSON} ${INCREMENTAL_FILE} || { errormsg "Error renaming ${INCREMENTAL_BSON} to ${INCREMENTAL_FILE}"; }

  gzip ${INCREMENTAL_FILE} || { errormsg "Error compressing ${INCREMENTAL_FILE}"; }
  echo "Stored incremental backup as ${INCREMENTAL_FILE}.gz"
}

storeIncrementalBackup () {
  local INCREMENTAL_FILE="${INCREMENTAL_PATH}/oplog.${NOW}.bson.gz"
  local remote_path="${BACKUP_USER}@${BACKUP_SERVER}:${INCREMENTAL_FILE}"

  echo "Transferring ${INCREMENTAL_FILE} to ${BACKUP_USER}@${BACKUP_SERVER}"
  if [ ! -e "${INCREMENTAL_FILE}" ]; then
    errormsg "${INCREMENTAL_FILE} not found!"
  fi

  scp ${INCREMENTAL_FILE} ${remote_path} || { removeIncrementalBackup; errormsg "Error transferring ${INCREMENTAL_FILE} to ${remote_path}"; }
}

removeIncrementalBackup () {
  local INCREMENTAL_FILE="${INCREMENTAL_PATH}/oplog.${NOW}.bson.gz"

  echo "Removing ${INCREMENTAL_FILE} from local server"
  rm -f ${INCREMENTAL_FILE} || { errormsg "Error removing ${INCREMENTAL_FILE} from local" ; }
}


####################### RESTORE ############################

### FULL ###

restoreFullBackup () {
  local mongo_user='mongodb'
  local mongo_group='mongodb'

  echo "  Creating ${RESTORE_NAME} volume, size ${VOLUME_SIZE}, in ${LVM_GROUP}"
  /sbin/lvcreate --size $VOLUME_SIZE --name $RESTORE_NAME $LVM_GROUP || { errormsg "${RESTORE_PATH} creation failed"; }
  echo "  Creating file system ${FS_TYPE} in ${RESTORE_PATH}"
  /sbin/mkfs -t ${FS_TYPE} ${RESTORE_PATH} || { errormsg "Failed creating ${FS_TYPE} in ${RESTORE_PATH}"; }
  echo "  Tunninng reserved space in ${RESTORE_PATH}"
  /sbin/tune2fs -m 0 ${RESTORE_PATH} || { echo "  WARNING: Failed tunning ${RESTORE_PATH}"; }

  if [ ! -e ${RESTORE_FILE} ]; then
    errormsg "${RESTORE_FILE} not found or permission problem"
  fi

  echo "  Restoring full backup from ${RESTORE_FILE} to ${RESTORE_PATH}"

  gzip -d -c ${RESTORE_FILE} | dd of=${RESTORE_PATH} status=progress || { echo "  WARNING: Restore didn't finished with 0 exit code (sometimes could be safely ignored)"; }

  local dmesg_error=`/bin/dmesg -T | tail -5 | grep 'exceeds size of device'`
  if [ ! -z "${dmesg_error}" ]; then 
    errormsg "Restoring ${RESTORE_FILE} to ${RESTORE_PATH}; Volume too small? ${dmesg_error}"
  fi

  echo "Mounting data..."
  if [ ! -d ${MONGODB_DATA} ]; then
    echo " WARNING: ${MONGODB_DATA} not found, trying to create the dir..."
    mkdir -p ${MONGODB_DATA} || { errormsg "Error creating dir ${MONGODB_DATA}"; }
    chown -R ${mongo_user}:${mongo_group} ${MONGODB_DATA}
  fi

  /bin/mount ${RESTORE_PATH} ${MONGODB_DATA} || { errormsg "Error mounting ${RESTORE_PATH} in ${MONGODB_DATA}"; }
  echo "  Success!"
}


### INCREMENTAL ###
restoreIncrementalBackup () {
  local TMP_FOLDER='/tmp/mongorestore'
  local TMP_FILE="${TMP_FOLDER}/oplog.bson.gz"

  echo "  Restoring ${RESTORE_FILE}"
  if [ ! -e ${RESTORE_FILE} ]; then
    errormsg "${RESTORE_FILE} not found or permission problem"
  fi

  if [ ! -d ${TMP_FOLDER} ]; then
    mkdir ${TMP_FOLDER}
  fi

  cp ${RESTORE_FILE} ${TMP_FILE} || { errormsg "Failed creating temporary ${TMP_FILE}"; }
  
  local file_type=`file ${TMP_FILE} | grep compressed`
  if [ ! -z "${file_type}" ]; then
    echo "  Decompressing ${TMP_FILE}"
    gzip -d ${TMP_FILE} || { errormsg "Failed decompressing ${TMP_FILE}"; }
  fi

  echo "  Replaying ${TMP_FOLDER}/oplog.bson"
  /usr/bin/mongorestore --oplogReplay ${TMP_FOLDER} || { errormsg "Problem restoring ${RESTORE_FILE} from ${TMP_FOLDER}/oplog.bson"; }
  rm -rf ${TMP_FOLDER}
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
#  stopMongo
  archiveIncrementalBackup
  lastOplogPosition
  storeIncrementalBackup
  removeIncrementalBackup
#  startMongo
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
  #stopMongo
  restoreFullBackup
  #startMongo
}

setupIncrementalRestore () {
  #stopMongo
  restoreIncrementalBackup
  #startMongo
}

#######################################

setup () {
  FULL_PATH="${BACKUP_PATH}/full"
  INCREMENTAL_PATH="${BACKUP_PATH}/incremental"

  INCREMENTAL_JSON="${INCREMENTAL_PATH}/local/oplog.rs.metadata.json"
  INCREMENTAL_BSON="${INCREMENTAL_PATH}/local/oplog.rs.bson"

  SNAPSHOT_PATH="/dev/${LVM_GROUP}/${SNAPSHOT_NAME}"

  LVM_PATH="/dev/${LVM_GROUP}/${LVM_NAME}"

  RESTORE_PATH="/dev/${LVM_GROUP}/${RESTORE_NAME}"

  if $BACKUP && $RESTORE; then
    errormsg 'Select either backup or restore'
  elif $BACKUP && [ ! -z "$BACKUP_MODE" ] && [ ! -z "${BACKUP_USER}" ] && [ ! -z "${BACKUP_SERVER}" ]&& [ -z "$RESTORE_FILE" ]; then
    setupBackup
  elif $RESTORE && [ ! -z "$RESTORE_MODE" ] && [ ! -z "$RESTORE_FILE" ]; then
    setupRestore
  else
    errormsg 'Something went wrong. Check the arguments'
  fi
}

usage () {
  echo "Backup or restore a mongo database, both incremental and full backups."
  echo " Usage:"
  echo "  $(basename $0) -B \$backup_mode [-S \$volume_size] [-P \$backup_path] [options] " 
  echo "  $(basename $0) -R \$restore_mode -f \$restore_file [options] "
  echo ""
  echo " -B \$backup_mode   : Perform backup in a backup_mode, either 'full' or 'incremental'"
  echo " -u \$backup_user   :  Set the user to ssh where mongo backup is going to be stored"
  echo "                        Only used and needed for backups. Ignored otherwise"
  echo " -H \$backup_host   :  Set the host to ssh where mongo backup is going to be stored"
  echo "                        Only used and needed for backups. Ignored otherwise"

  echo " -P \$backup_path   : Optional: Set the directory where the backups will be stored"
  echo "                       default: '/backup/mongo'"

  echo ""
  echo " -R \$restore_mode  : Restore a type of backup, either 'full' or 'incremental'"
  echo " -f \$restore_file  : Set the file from which the restore will be done"
  echo " -D \$database_path : Optional: Path to mongo database files. Only for full restore."
  echo "                       default: '/data'"
  echo ""
  echo " Options:"
  echo "  -S \$volume_size  :  Specify the max size of the Virtual Volume (optional). Used for Full mode. Ignored otherwise"
  echo "                       In Backup, used as Snapshot max. size"
  echo "                       default: '100G'"
  echo "  -G \$lvm_group    :  Set the LVM group where mongo data is, or where is going to be (optional)"
  echo "                       default: 'mongo_data'"
  echo "  -V \$lvm_name     :  Set the LVM Volume name where mongo data is, or where is going to be (optional)"
  echo "                       Only used for Full Backup. Ignored otherwise"
  echo "                       default: 'mongodata'"
  echo "  -t \$last_op_time :  Set the path to the file where the last oplog time is stored, or where is going to be (optional)"
  echo "                       default: '/opt/mongo_last_oplog.time'"
  echo ""
  echo " -h : Usage. Prints this text"
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
    -S) VOLUME_SIZE=$2; shift 2;;
    -u) BACKUP_USER=$2; shift 2;;
    -H) BACKUP_SERVER=$2; shift 2;;

    -R) RESTORE=true; RESTORE_MODE=$2; shift 2;;
    -f) RESTORE_FILE=$2; shift 2;;
    -D) MONGODB_DATA=$2; shift 2;;

    -P) BACKUP_PATH=$2; shift 2;;

    -G) LVM_GROUP=$2; shift 2;;
    -V) LVM_NAME=$2; shift 2;;
    -t) LAST_OPLOG_FILE=$2; shift 2;;

    -h) usage; exit 0;;
    *) usage; echo ""; echo "ERROR: Invalid option"; exit 2;;
  esac
done

setup
