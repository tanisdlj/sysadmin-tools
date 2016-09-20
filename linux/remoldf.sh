#!/bin/bash

# Removes files older than X given days from a specific folder.
# 19/09/2016 diego.lucas.jimenez@gmail.com initial version

regexNumber='^[0-9][0-9]?[0-9]?$'
DAYS=
FOLDER=""

# Default: Do NOT simulate, NOT quiet.
simulate=0
quiet=0

setup () {
  checkFolder
  simulate
  info
  remove
}

checkFolder () {
  if [ ! -d "$FOLDER" ]; then
    echo "ERROR: Given folder "$FOLDER" doesn't exists. Exiting..."
    exit 1
  fi
}

info () {
  if [ $quiet -ne 1 ]; then
    deleteCount=`find "$FOLDER" -maxdepth 1 -type f -mtime +${DAYS} | wc -l`
    totalCount=`find "$FOLDER" -maxdepth 1 -type f | wc -l`
    echo "$deleteCount of $totalCount removed, keeping $(( $totalCount-$deleteCount ))"
  fi
}

simulate () {
  if [ $simulate -eq 1 ]; then
    echo ""
    echo "Deleted files: "
    find "$FOLDER" -maxdepth 1 -type f -mtime +${DAYS} | sort
    echo ""
    echo "Files left: "
    find "$FOLDER" -maxdepth 1 -type f -mtime ${DAYS}
    find "$FOLDER" -maxdepth 1 -type f -mtime -${DAYS} | sort
    echo ""
    info
    exit 0
  fi
}

remove () {
  find "$FOLDER" -maxdepth 1 -type f -mtime +${DAYS} -delete
}

usage () {
  echo "  Remove files older than \$days files in a given \$path."
  echo "  Usage: remoldf.sh [-h|--help] | [-k \$days] [-f \$path]"
  echo ""
  echo "      -h   :   Shows this message"
  echo "      -q   :   Remove info messages"
  echo "      -s   :   Just a simulation, does not remove anything"
  echo "      -k \$days     :   Keep files up to \$days old"
  echo "      -f \$path     :   Path were the files are stored"
}

# Number of arguments check
if [ "$#" -lt 4 ] ; then
  echo "ERROR: Wrong arguments please check usage"
  usage
  exit 2
fi

## Arguments
while [ "$#" -gt 0 ]; do
  case $1 in
    -k) if [[ $2 =~ $regexNumber ]] ; then
          DAYS="$2"
          shift 2
        else
          echo "ERROR: Need a number of days"
          exit 2
        fi
        ;;
    -f) FOLDER="$2"; shift 2;;
    -q) quiet=1; shift 1;;
    -s) simulate=1; shift 1;;
    -h) usage; exit 0;;
    *) echo "ERROR: Invalid option ($opt)"; usage; exit 2;;
  esac
done

setup
