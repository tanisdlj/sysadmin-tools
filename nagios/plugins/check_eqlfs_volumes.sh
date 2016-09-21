#!/bin/bash

# Nagios script to discover or check Dell Equallogic FluidFS Volumes.
# Needs to read the MIBS file that you should find under:
# ftp://yourEQLipORurl:44421/mibs/FluidFS-MIB.txt
# You should place it under /usr/share/mibs/ with rx perms so Nagios
# can read it or properly install it for your SNMP in your nagios host

# 19/09/2016 diego.lucas.jimenez@gmail.com initial version

SNMP_HOST=""
COMMUNITY="public"
MIB_FILE="/usr/share/mibs/FluidFS-MIB.txt"
WARNING=90
CRITICAL=95

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
    -v) volume="$2"; shift 2;;
    -w) warning="$2"; shift 2;;
    -c) critical="$2"; shift 2;;

    # Other args
    -h) usage; exit 0;;
    --help) usage; exit 0;;
    *) echo "ERROR: Unknown option $1"; usage; exit 1;;
  esac
done

