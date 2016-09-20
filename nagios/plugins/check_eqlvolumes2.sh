#!/bin/bash


$snmpTrap=""
$snmpHost=""

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
#  local perc=`bc <<< "scale=2;$used*100/$total"`
  local perc=`echo "scale=2;$used*100/$total" | bc | sed 's/^\./0./'`
  echo $perc
}

checkAll () {
  VOLIDS=`snmpwalk -m /root/.snmp/mibs/FluidFS-MIB.txt -v2c -c $snmpTrap $snmpHost FLUIDFS-MIB::nASVolumeIndex | cut -d' ' -f 4`
  echo "Volume Name (ID) Used Space / Total Space (Percentage Used)"
  echo "############################################"

  for ID in $VOLIDS; do
    VolName=`snmpwalk -O Qv -m /root/.snmp/mibs/FluidFS-MIB.txt -v2c -c $snmpTrap $snmpHost FLUIDFS-MIB::nASVolumeVolumeName.$ID`
    VolName=${VolName//\"}
    VolSize=`snmpwalk -O Qv -m /root/.snmp/mibs/FluidFS-MIB.txt -v2c -c $snmpTrap $snmpHost FLUIDFS-MIB::nASVolumeSizeMB.$ID`
    VolSize=${VolSize//\"}
    VolUsed=`snmpwalk -O Qv -m /root/.snmp/mibs/FluidFS-MIB.txt -v2c -c $snmpTrap $snmpHost FLUIDFS-MIB::nASVolumeUsedSpaceMB.$ID`
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
    -S) option=1; shift 1;;
    -s) option=2; shift 1;;
    -G) option=3; shift 1;;
    -g) option=4; shift 1;;

    # Parameters
    -n) nagios="$2"; shift 2;;
    -U) user="$2"; shift 2;;
    -p) password="$2"; shift 2;;

    --nagios=*) nagios="${1#*=}"; shift 1;;
    --user=*) user="${1#*=}"; shift 1;;
    --password=*) password="${1#*=}"; shift 1;;
    --nagios|--user|--password) echo "$1 requires an argument" >&2; exit 1;;

    # Specific arguments
    -T) target="$2"; shift 2;;
    -f) startTime="$2"; shift 2;;
    -t) endTime="$2"; shift 2;;
    -h) hostName="$2"; shift 2;;

    --target=*) target="${1#*=}"; shift 1;;
    --from=*) startTime="${1#*=}"; shift 1;;
    --to=*) endTime="${1#*=}"; shift 1;;
    --hostname=*) hostName="${1#*=}"; shift 1;;
    --target|--from|--to) echo "$1 requires an argument" >&2; exit 1;;

    # Other args
    -u) usage; exit 0;;
    --usage) usage; exit 0;;
    -*) echo "unknown option: $1" >&2; exit 1;;
    *) commentary="$commentary $1"; shift 1;;
  esac
done

