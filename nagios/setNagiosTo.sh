#!/bin/bash
#
# Title       :setNagiosTo.sh
# Description :Send orders to Nagios 1/2/3 through the web interface.
# Author      :Diego Lucas Jimenez (diego.lucas.jimenez@gmail.com)
# Date        :20150812
# Version     :1.0
# Usage       :bash setNagiosTo.sh <> 
# Updates     : 
#              12/08/2015 diego.lucas.jimenez@gmail.com initial version

readonly VERSION="1.0a"
option=
nagios=""
user=""
password=""
target=""
hostName=""
startTime=
endTime=
commentary=""
readonly NOW=$(date '+%Y-%m-%d %H:%M:%S')
curlCommonArgs=""
curlSpecificArgs=""

readonly DOWN_HOST=55
readonly DOWN_ALL_SERVICES=86
readonly DOWN_SERVICE=56

usage () {
    echo "  Usage: setNagiosTo.sh [-h]|[-H|-S|-s|-G|-g] args ... [description]"
    echo ""
    echo "         -u | --usage  :   Shows this message"
    echo "         -H            :   Host to maintenance"
    echo "         -S            :   All services in a Host to maintenance"
    echo "         -s            :   Service to maintenance "
    echo "         -G            :   Host Group to maintenance "
    echo "         -g            :   Service Group to maintenance "
    echo ""
    echo "         args "
    echo "         -n \$NAGIOSURL | --nagios=\$NAGIOSURL :   Nagios URL "
    echo "         -U \$USER | --user=\$USER             :   User name "
    echo "         -p \$PASSWORD | --password=\$PASSWORD :   Password "
    echo ""
    echo "         -T \$TARGET | --target=\$TARGET       :   Target Host/Service/Service Group/Host Group "
    echo "         [-h \$hostName | hostname=\$hostName] :   Only when Target = Service (-s). Hostname "
    echo "                                                   where the service is located. "
    echo "         -f \$STARTTIME| --from=\$STARTTIME    :   Maintenance start time with format \"+%Y-%m-%d %H:%M:%S\" "
    echo "                                                   Examples: --from=1988-05-05 08:15:34 "
    echo "                                                             --from=now "
    echo "         -t \$ENDTIME | --to=\$ENDTIME         :   Maintenance end time with the same format than -f "
    echo "         description                           :   Any sentence will be used as description for the maintenance."
    exit 0;
}

checkStartDate () {
    NOWSEC=$(date -d "$NOW" +%s)
    STARTSEC=$(date -d "$startTime" +%s)
    ENDSEC=$(date -d "$endTime" +%s)
    if [[ $NOWSEC -gt $STARTSEC ]]; then
        echo "ERROR: Start date is previous than now: $NOW \
           Please, select a date in the future, not in the past."
        exit 1
    elif [ $NOWSEC -gt $ENDSEC ]; then
        echo "ERROR: End date is previous than now: $NOW \
           Please, select a date in the future, not in the past."
        exit 1
    elif [[ $STARTSEC -gt $ENDSEC ]]; then
        echo "ERROR: End date is previous than start date. Time flows forward, not backwards."
        exit 1
    fi       
}

hostOption () {
    echo "Scheduling maintenance for $target host from $startTime to $endTime"
    curlSpecificArgs="cmd_typ=$DOWN_HOST&cmd_mod=2&com_data=$commentary&trigger=0&start_time=$startTime&end_time=$endTime&fixed=1&hours=0&minutes=0&host=$target"
}

servicesOption () {
    echo "Scheduling maintenance for $target host services from $startTime to $endTime"
    curlSpecificArgs="cmd_typ=$DOWN_ALL_SERVICES&cmd_mod=2&com_data=$commentary&trigger=0&start_time=$startTime&end_time=$endTime&fixed=1&hours=0&minutes=0&host=$target"
 #   curl -u $USER:$PASSWORD -d "cmd_typ=$DOWN_ALL_SERVICES&cmd_mod=2&com_data=$COMMENT&trigger=0&start_time=$STARTTIME&end_time=$ENDTIME&fixed=1&hours=0&minutes=0&host=$HOST" $NAGIOSURL/nagios3/cgi-bin/cmd.cgi
}

serviceOption () {
    echo "Scheduling maintenance for $target service on $hostName from $startTime to $endTime"
    curlSpecificArgs="cmd_typ=$DOWN_SERVICE&cmd_mod=2&com_data=$commentary&trigger=0&start_time=$startTime&end_time=$endTime&fixed=1&hours=0&minutes=0&host=$hostName&service=$target"
}

hostGroupOption () {
    echo "Not implemented yet."
    exit 1;
}

serviceGroupOption () {
    echo "Not implemented yet."
    exit 1;
}

processOutput () {
    if [ $1 == "Your command request was successfully submitted to Nagios for processing." ]; then
       echo "Maintenance scheduled"
    else
       echo $1
       exit 2 
    fi
}

startMaintenance () {
    curlCommonArgs="-u $user:$password $nagios/nagios3/cgi-bin/cmd.cgi"
    output=`curl -s -d "$curlSpecificArgs" $curlCommonArgs | grep "infoMessage" | sed -e "s/.*infoMessage'>//" -e "s/<BR.*//"`

    if [ $? -eq 0 ]; then
        processOutput $output
    else
        echo "[ERROR] Ooops, something went wrong."
        exit 1
    fi
}

optionManager () {
    case "$option" in
        0) hostOption;;
        1) servicesOption;;
        2) serviceOption;;
        3) hostGroupOption;;
        4) serviceGroupOption;;
        *) echo "Wrong option selected. Review the script."; exit 1;;
    esac
}

checkArgs() {
  if [ $startTime = "now" ]; then
    startTime=$NOW
  fi

  if [ $option -eq 2 ]; then
    if [ $hostName = "" ]; then
      echo "ERROR: For this option you need to provide a hostName."
      usage
      exit 1
    fi
  fi
}

setup () {
    checkArgs
    checkStartDate
    optionManager
    startMaintenance
    exit 0
}

if [ $# -eq 0 ]; then
  usage
  exit 1;
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    # Select operation to perform
    -H) option=0; shift 1;;
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
    -u) usage;;
    --usage) usage;;
    -*) echo "unknown option: $1" >&2; exit 1;;
    *) commentary="$commentary $1"; shift 1;;
  esac
done

setup
