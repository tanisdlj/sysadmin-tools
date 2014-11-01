#!/bin/bash
# Creates the file with the LFTP commands needed to download the last backup files, then
# download the last backup and check the md5sum.
# If md5sum failed, then try to download the file again.
# 08/09/2014 diego.lucas.jimenez@gmail.com initial version

readonly LFTP="/usr/bin/lftp"
readonly LFTP_OPTIONS="-f"
readonly BACKUP_FILE=$(date +backupProject.'%Y%m%d')
readonly BOOKMARK="backupProject"
readonly BACKUP_FOLDER="/home/backupUser/backup1/backupProject/"
readonly SCRIPTNAME="/home/backupUser/backupProject-download.lftp"
readonly SCRIPTNAME_TEXT="open $BOOKMARK\nmget -O $BACKUP_FOLDER $BACKUP_FILE*"
# Testing SCRIPTNAME_TEXT "open $BOOKMARK\nnlist $BACKUP_FILE*"
# Default SCRIPTNAME_TEXT "open $BOOKMARK\nmget -O $BACKUP_FOLDER $BACKUP_FILE*"
readonly MAX_ATTEMPTS=3
attempt=0

# Display error messages and exit.
error() {
        echo "$(date +'%Y %h %d %H:%M:%S') [ERROR] $1"
        exit 1
}

# Displays a message with info level
info () {
        echo "$(date +'%Y %h %d %H:%M:%S') [INFO] $1"
}

## Displays a message with warning level
warning() {
	echo "$(date +'%Y %h %d %H:%M:%S') [WARNING] $1"
}

# Show a message to teach how to use this script
usage() {
        cat <<EOF
Usage:
        `basename $0`
        Download and check daily issuetracker backup and stores it in $BACKUP_FOLDER

        `basename $0` -h
        displays this message.
EOF
}

# Create a file to be used on lftp to download the backups.
createLftpFile() {
	info "Creating script for lftp..."
	echo -e $SCRIPTNAME_TEXT > $SCRIPTNAME
}

# Check if the backup is already donwloaded
checkExistingFiles() {
	if [ -f $BACKUP_FOLDER$BACKUP_FILE.tgz ]; then
		warning "Last backup already downloaded"
		md5CheckSum
		exit 0
	fi
}

# Download the files using lftp and removes the temporal script.
downloadFiles() {
	info "Downloading files..."
	$LFTP $LFTP_OPTIONS $SCRIPTNAME
	rm $SCRIPTNAME
}

#Check that the desired files has been downloaded.
checkDownloads() {
	local numberOfFiles=$(ls $BACKUP_FOLDER | grep -c $BACKUP_FILE)

	if [ ! -f $BACKUP_FOLDER$BACKUP_FILE.tgz ] || [ ! -f $BACKUP_FOLDER$BACKUP_FILE.md5 ]; then
                error "No files downloaded. Exiting..."
	elif [ $numberOfFiles -ne 2 ]; then
		warning "Wrong number of files found!!!!!"
	fi
}


retryDownload() {
	if [ ! "$attempt" -ge "$MAX_ATTEMPTS" ]; then
		info "$BACKUP_FILE.md5 md5sum does not match with $BACKUP_FILE.tgz, downloading again"
		attempt=$attempt+1
        	downloadFiles
	else
                error "md5sum is not matching after $MAX_ATTEMPTS download attempts. Exiting..."
	fi
}

md5CheckSum() {
	local md5hash=$(md5sum $BACKUP_FOLDER$BACKUP_FILE.tgz)
	# Remove substring with the Backup Folder path
	local md5hash=${md5hash/$BACKUP_FOLDER/}
	if [ "$(cat $BACKUP_FOLDER$BACKUP_FILE.md5)" = "$md5hash" ]; then 
		info "Downloaded file is OK"; 
	else
		retryDownload
	fi
}

main() {
	checkExistingFiles
	createLftpFile
	downloadFiles
	checkDownloads
	md5CheckSum
	exit 0
}

## Arguments
while getopts brd:hf opt; do
    case $opt in
        h)
                usage
                exit 0
                ;;
		\?)
                echo "ERROR: invalid option ($opt)"
                usage
                exit 1
                ;;
    esac
done

main
