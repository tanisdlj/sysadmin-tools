#!/bin/bash

# /usr/share/mibs/ with rx perms - FluidFS-MIB.txt

COMMUNITY=""
SNMP_HOST=""
MIB_FILE=""

toXB () {
  local arg1=$1
  local inGB=`bc <<< "scale=2;${arg1}/1024"`

  if [ ${inGB%.*} -ge 1024 ]; then
    local inTB=`bc <<< "scale=2;${inGB}/1024"`
    echo "$inTB TB"
  elif [ ${inGB%.*} -ge 1 ]; then
    echo "$inGB GB"
  else
    echo "$arg1 MB"
  fi
}

toPercentage () {
  local used=$1
  local total=$2
  local perc=`echo "scale=2;$used*100/$total" | bc | sed 's/^\./0./'`
  echo $perc
}

checkAll () {
  VOLIDS=`snmpwalk -m $MIB_FILE -v2c -c $COMMUNITY $SNMP_HOST FLUIDFS-MIB::nASVolumeIndex | cut -d' ' -f 4`
  echo "Volume Name (ID) Used Space / Total Space (Percentage Used)"
  echo "############################################"

  for ID in $VOLIDS; do
    VolName=`snmpwalk -O Qv -m $MIB_FILE -v2c -c $COMMUNITY $SNMP_HOST FLUIDFS-MIB::nASVolumeVolumeName.$ID`
    VolName=${VolName//\"}
    VolSize=`snmpwalk -O Qv -m $MIB_FILE -v2c -c $COMMUNITY $SNMP_HOST FLUIDFS-MIB::nASVolumeSizeMB.$ID`
    VolSize=${VolSize//\"}
    VolUsed=`snmpwalk -O Qv -m $MIB_FILE -v2c -c $COMMUNITY $SNMP_HOST FLUIDFS-MIB::nASVolumeUsedSpaceMB.$ID`
    VolUsed=${VolUsed//\"}

    Size=$(toXB $VolSize)
    Used=$(toXB $VolUsed)
    PercUsed=$(toPercentage ${VolUsed} ${VolSize})

    echo "$VolName (${ID//\"}) $Used / $Size ($PercUsed %)"
  done
}

# Args management

while [ "$#" -gt 0 ]; do
  case "$1" in
    # Select operation to perform
    -D) checkAll; exit 0;;

    # Parameters
    -H) SNMP_HOST=="$2"; shift 2;;
    -C) COMMUNITY="$2"; shift 2;;
    -m) MIB_FILE="$2"; shift 2;;

    # Specific arguments
    -v) target="$2"; shift 2;;
    -w) startTime="$2"; shift 2;;
    -c) endTime="$2"; shift 2;;

    # Other args
    -h) usage; exit 0;;
    --help) usage; exit 0;;
    *) echo "ERROR: Unknown option $1"; usage; exit 1;;
  esac
done

