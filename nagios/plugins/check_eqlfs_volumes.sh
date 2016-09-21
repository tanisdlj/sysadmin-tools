#!/bin/bash

# Nagios script to discover or check Dell Equallogic FluidFS Volumes.
# Needs to read the MIBS file that you should find under:
# ftp://yourEQLipORurl:44421/mibs/FluidFS-MIB.txt
# You should place it under /usr/share/mibs/ with rx perms so Nagios
# can read it or properly install it for your SNMP in your nagios host

# 19/09/2016 diego.lucas.jimenez@gmail.com initial version

discover=0
SNMP_HOST=""
COMMUNITY="public"
MIB_FILE="/usr/share/mibs/FluidFS-MIB.txt"
volume=""
WARNING=90
CRITICAL=95

setup () {
  checkArgs
  checkVolume
}

checkArgs () {
  # Host
  if [ -z "$SNMP_HOST" ]; then
    echo "ERROR: No host defined"
    exit 3
  fi
  # Volume
  if [ "$discover" -eq 0 ] && [ -z "$volume" ]; then
    echo "ERROR: No volume defined"
    exit 3
  fi
  # Check MIB file
  if [ ! -r "$MIB_FILE" ]; then
    echo "ERROR: MIB file not found or permission problem"
    exit 3
  fi
}

usage () {
  echo "  Discover or check Dell Equallogic FluidFS Volumes."
  echo "  Usage: check_eqlfs_volumes.sh [-h|--help] | [-D] | [-H \$HOST] [-C \$COMMUNITY] [-M \$MIB] [-v \$volume] [-w \$warning] [-c \$critical]"
  echo "  ~# check_eqlfs_volumes.sh -H eql.acme.com -C communString -v volume_users -w 80 -c 90"
  echo "  30 of 120 removed, keeping 90"
  echo ""
  echo "    -h | --help   : Shows this message"
  echo "    -D            : Shows all the volumes"
  echo "    -H \$host     : Host or ip"
  echo "    -C \$community: SNMP Community string (default public)"
  echo "    -M \$MIB      : FluidFS MIB file (default /usr/share/mibs/FluidFS-MIB.txt)"
  echo "    -v \$volume   : Volume to check"
  echo "    -w \$warning  : Warning level (default 90%)"
  echo "    -c \$critical : Critical level (default 95%)"
}

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

getVolData () {
  local VolID=$1
  local VolName=$2

  local VolSize=`snmpwalk -O Qv -m $MIB_FILE -v2c -c $COMMUNITY $SNMP_HOST FLUIDFS-MIB::nASVolumeSizeMB.$VolID`
  local VolSize=${VolSize//\"}
  local VolUsed=`snmpwalk -O Qv -m $MIB_FILE -v2c -c $COMMUNITY $SNMP_HOST FLUIDFS-MIB::nASVolumeUsedSpaceMB.$VolID`
  local VolUsed=${VolUsed//\"}

  local Size=$(toXB $VolSize)
  local Used=$(toXB $VolUsed)
  local PercUsed=$(toPercentage ${VolUsed} ${VolSize})

  local volData="$VolName ($PercUsed %) $Used / $Size (ID ${VolID//\"})"

  if [ $discover -eq 0 ]; then
    checkUsage "$PercUsed" "$volData"
  else
    echo "$volData"
  fi
}

checkVolume () {
  local volFound=0
  # Discovery mode
  if [ $discover -eq 1 ]; then
    echo "Volume Name (Percentage Used) Used Space / Total Space (ID)"
    echo "###########################################################"
  fi

  # Checking volumes
  local VOLIDS=`snmpwalk -m $MIB_FILE -v2c -c $COMMUNITY $SNMP_HOST FLUIDFS-MIB::nASVolumeIndex | cut -d' ' -f 4`
  for ID in $VOLIDS; do
    # Getting Volume Name and cleaning it.
    VolName=`snmpwalk -O Qv -m $MIB_FILE -v2c -c $COMMUNITY $SNMP_HOST FLUIDFS-MIB::nASVolumeVolumeName.$ID`
    VolName=${VolName//\"}

    if [ "$VolName" == "$volume" ] || [ $discover -eq 1 ]; then
      volFound=1
      getVolData "$ID" "$VolName"
    fi
  done

  if [ $volFound -eq 0 ]; then
    echo "ERROR: Requested volume not found"
    exit 3
  fi
}

checkUsage () {
  local perc=$1
  local volData="$2"
  local checkStatus="UNKNOWN:"
  local exitCode=3

  if [ ${perc%.*} -ge $CRITICAL ]; then
    checkStatus="CRITICAL:"
    exitCode=2
  elif [ ${perc%.*} -ge $WARNING ]; then
    checkStatus="WARNING:"
    exitCode=1
  else
    checkStatus="OK:"
    exitCode=0
  fi

  echo "$checkStatus $volData"
  exit $exitCode
}

# Args management

if [ "$#" -eq 0 ]; then
  echo "ERROR: Arguments required"
  usage
  exit 3
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    # Select operation to perform
    -D) discover=1; shift 1;;

    # Parameters
    -H) SNMP_HOST="$2"; shift 2;;
    -C) COMMUNITY="$2"; shift 2;;
    -M) MIB_FILE="$2"; shift 2;;

    # Specific arguments
    -v) volume="$2"; shift 2;;
    -w) warning="$2"; shift 2;;
    -c) critical="$2"; shift 2;;

    # Other args
    -h) usage; exit 0;;
    --help) usage; exit 0;;
    *) echo "ERROR: Unknown option $1"; usage; exit 3;;
  esac
done

setup
