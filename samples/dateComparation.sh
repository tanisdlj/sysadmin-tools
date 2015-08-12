#!/bin/bash
# usage: dateComparation.sh "2015-09-29 17:10:45"
set -e
readonly NOW=$(date '+%Y-%m-%d %H:%M:%S')
NOWSEC=
readonly END=$1
ENDSEC=

detectOS () {
	if [[ "$OSTYPE" == "linux-gnu" ]]; then
	        echo "Linux distro detected"
		dateToEpochLinux
	elif [[ "$OSTYPE" == "darwin"* ]]; then
	        echo "MacOS detected"
		dateToEpochMac
	elif [[ "$OSTYPE" == "cygwin" ]]; then
	        echo "Cygwin detected"
		dateToEpochLinux
	elif [[ "$OSTYPE" == "msys" ]]; then
		echo "Windows detected"
		wrongOS
	elif [[ "$OSTYPE" == "freebsd"* ]]; then
	        echo "FreeBSD detected"
		wrongOS
	else
	        echo "Unknow OS"
		wrongOS
	fi
}

wrongOS () {
	echo "Sorry, your OS is not compatible with this script".
	exit 1
}

dateToEpochLinux () {
	NOWSEC=$(date -d "$NOW" +%s)
        ENDSEC=$(date -d "$END" +%s)
}

dateToEpochMac () {
	NOWSEC=$(date -j -f '%Y-%m-%d %H:%M:%S' "$NOW" +%s)
        ENDSEC=$(date -j -f '%Y-%m-%d %H:%M:%S' "$END" +%s)
}

compareDates () {
	echo "comparing $NOW with $END"

	if [[ $NOWSEC -gt $ENDSEC ]]; then 
		echo "$END is previous to $NOW"
	else
		echo "$END is later than $NOW"
	fi
}

usage () {
	echo "    Usage:    dateComparation.sh \"2015-09-29 17:10:45\""
}

checkArgs () {
	if [ $# -eq 1 ]; then
		echo ""
	else
		echo "Wrong amount of arguments: $#"
		usage
		exit 0
	fi
}

setup () {
#	checkArgs $@
	detectOS
	compareDates
}

setup $@
