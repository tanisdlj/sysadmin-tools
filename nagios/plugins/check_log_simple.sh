#! /bin/bash
#
# Title		:check_log_simple.sh
# Description	:Check if there was any error in the last "n" lines of the log (default 50)
# Author		:Diego Lucas Jimenez (diego.lucas.jimenez@gmail.com)
# Date		:20140514
# Version	:0.9
# Usage		:bash check_log_simple.sh <logfile>
# Notes		:It search for error, critical and exception keywords

# Define search keywords
ERRORSTRING="error\|critical\|exception\|abort:\|failed\|ssh_exchange_identification:\\sConnection\\sclosed\\sby\\sremote\\shost"
WARNINGSTRING="warning\|failed\\sto\\sunmount"
# Define exceptions
IGNOREDERRORS="Errors\\s0\|Errno\\s13\|Error\\slisting\\sdirectory\\|dropbox\|failed\\sto\\sunmount\|$ERROR_LFTP"
IGNOREDWARNINGS="Lolcat"
ERROR_LFTP="mget: execvp() failed: No such file or directory"

#Define log read lines
LINES="-50"

#Define Nagios exit states
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

main(){
  logfile=$1
  checkParameters $*
  checkLog $logfile
}

usage(){
          cat <<EOF
 USAGE:
  check_log_simple <logfile>
   where:
          <logfile> log file to be read 
EOF
}

checkLog(){
  logfile=$1
#Number of errors found
  errorsFound=`tail $LINES $logfile | grep -i $ERRORSTRING | grep -c -v -i $IGNOREDERRORS`
  warningsFound=`tail $LINES $logfile | grep -i $WARNINGSTRING | grep -c -v -i $IGNOREDWARNINGS`

  if [ "$errorsFound" -gt "0" ]
  then
    errorStrings=`tail $LINES $logfile | grep -A 1 -i $ERRORSTRING | grep -v -i $IGNOREDERRORS`
    echo "CRITICAL : $errorsFound ERRORS FOUND:
$errorStrings"
    exit $STATE_CRITICAL
  elif [ "$warningsFound" -gt "0" ]
  then
    warningStrings=`tail $LINES $logfile | grep -A 1 -i $WARNINGSTRING | grep -v -i $IGNOREDWARNINGS`
    echo "WARNING : $warningsFound WARNINGS FOUND:
$warningStrings"
    exit $STATE_WARNING
  else
    #Create file with the date of the last successful check
    echo "OK - NO ERRORS at $logfile "
    exit $STATE_OK
  fi
}

checkParameters(){
  logfile=$1

  if [ -z "$logfile" ]
  then
    usage
    error "missing parameters"
  fi

  if [ ! -f "$logfile" ]
  then
    error "invalid file"
  fi
}

error(){
  printf "$(date +'%F %T %z') `basename $0`: \e[0;31mERROR:\e[m $1\n" >&2
  exit $STATE_UNKNOWN
}

main $*
