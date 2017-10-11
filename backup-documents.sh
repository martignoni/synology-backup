#!/bin/sh
#
# This script is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This script is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this script. If not, see <http:#www.gnu.org/licenses/>.
#
# Copyright (c) 2017 onwards Nicolas Martignoni <nicolas@martignoni.net>
#
# #############################################################################
# Backup script for Synology
# Requires rsync 3 on machine to backup
# This should be scheduled to run every hour
# The script checks if a backup has completed before several hours (configurable)
# If this is not the case, it proceeds to do an effective backup
#
# Source: https://github.com/martignoni/synology-backup

# #############################################################################
# Uncomment to print debug messages in log file.
# DEBUG=1

# Get name and full path of this very script.
FULLPROG=$0
# Get filename of this very script.
PROG=${0##*/}
# Get full path of dir where this very script is stored.
BASEDIR=$(cd $(dirname $0); pwd -P)

USER="username-change-me"               # The username account on the machine to backup.
SERVERIP="192.168.1.10"                 # IP address of the machine to backup.
SERVERMACADDRESS="00:aa:11:bb:22:cc"    # MAC hardware address of the machine to backup. 
PORT="22"                               # SSH port open on the machine to backup.
SSHID="/root/.ssh/id_rsa"               # File on the Synology containing the SSH public key.
SRC="/Users/Shared/Documents/"          # Path to backup on the machine to backup.
DST="/volume1/Backup documents/"        # Where to put the backup on the Synology.
LOG="$BASEDIR/backup.log"               # Log file (on the Synology).
EXCLUDE="$BASEDIR/.backupignore"        # File containing files to ignore (on the Synology).

# Run only when lastbackup older than $MAXH hours.
MAXH=24

# Read last backup date from file.
BACKUPTIMESTAMP=$BASEDIR/lastdocbackup.txt
if [ -r ${BACKUPTIMESTAMP} ]; then
	LASTBACKUP=$(cat ${BACKUPTIMESTAMP})
else
	LASTBACKUP=$(date --date='yesterday' +%s)
	echo $LASTBACKUP >$BACKUPTIMESTAMP
fi

if [ $(( $(date +%s) - $LASTBACKUP )) -lt $((60*60*$MAXH)) ]; then
	# Exit as last backup is too recent.
	[[ "$DEBUG" ]] && echo "LAST BACKUP DATE: $(date -d @$LASTBACKUP +'%F %T'), SKIPPING" >>$LOG
	exit 0
else
	logger -t $PROG "===== $PROG "`date +"%F %T"`" ====="
	echo "===== $PROG "`date +"%F %T"`" =====" >>$LOG
	[[ "$DEBUG" ]] && echo "LAST BACKUP DATE: $(date -d @$LASTBACKUP +'%F %T'), OLDER THAN $MAXH HOURS" >>$LOG
fi

# --acls				   update the destination ACLs to be the same as the source ACLs
#				"acls" option doen't work if destination is not HFS+ formatted
# --archive				   turn on archive mode (recursive copy + retain attributes)
# --delete				   delete any files that have been deleted locally
# --delete-excluded		   delete any files (on DST) that are part of the list of excluded files
# --progress			   show progress during transfer
# --exclude-from		   reference a list of files to exclude
# --hard-links			   preserve hard-links
# --crtimes				   preserve create times (newness)
#				"crtimes" option doen't work on Synology (rsync 3.0.9)
# --one-file-system		   don't cross device boundaries (ignore mounted volumes)
# --sparse				   handle sparse files efficiently
# --verbose				   increase verbosity
# --human-readable		   output numbers in a human-readable format
# --xattrs				   update the remote extended attributes to be the same as the local ones
#				"xattrs" option doen't work if destination is not HFS+ formatted
# --stats				   give some file-transfer stats

# Try 5 times to get a ssh connection to host $SERVERIP.
for i in {1..5}; do
	[[ "$DEBUG" ]] && echo "STARTING LOOP #$i" >>$LOG
	ping -c1 -w5 -q $SERVERIP >/dev/null 2>&1
	# PING=$( ping -c1 -w5 -q $SERVERIP | grep "\s0%\s" | wc -l )
	if [ $? -ne 0 ] ; then
		# Ping failed. We try to wake up host $SERVERIP using synonet utility.
		[[ "$DEBUG" ]] && echo "PING NOK, trying wakeup" >>$LOG
		synonet --wake $SERVERMACADDRESS eth0 >>$LOG 2>&1
		# Wait a bit until host $SERVERIP is ready.
		sleep 10
	else
		[[ "$DEBUG" ]] && echo "PING OK, trying ssh" >>$LOG
	fi
	# Try to connect to $SERVERIP via ssh to test if we can start the sync process.
	ssh -q -o ConnectTimeout=5 -p $PORT -i $SSHID $USER@$SERVERIP exit 0 >>$LOG 2>&1
	if [ $? -ne 0 ] ; then
		# Connection failed
		SSHCONNECT=false
		[[ "$DEBUG" ]] && echo "SSHCONNECT NOK, continue loop" >>$LOG
	else
		# Host $SERVERIP is reachable via ssh. We exit the loop.
		SSHCONNECT=true
		[[ "$DEBUG" ]] && echo "SSHCONNECT OK, exit loop" >>$LOG
		break
	fi
done

if [ "$SSHCONNECT" = false ] ; then # Host is not reachable.
	logger -t $PROG "Source $SERVERIP is unreachable - Cannot start the sync process"
	echo "Source $SERVERIP is unreachable - Cannot start the sync process. Exiting" >>$LOG
	exit;
fi

if [ ! -w "$DST" ]; then # Destination folder is not writeable.
	logger -t $PROG "Destination $DST not writeable - Cannot start the sync process"
	echo "Destination $DST not writeable - Cannot start the sync process. Exiting" >>$LOG
	exit;
fi

# Start synchronisation process.
rsync --archive \
	  --delete \
	  --delete-excluded \
	  --exclude-from=$EXCLUDE \
	  --hard-links \
	  --one-file-system \
	  --sparse \
	  --verbose \
	  --fake-super \
	  --human-readable \
	  --rsync-path=/usr/local/bin/rsync \
	  -e "ssh -p $PORT -i $SSHID" $USER@$SERVERIP:"$SRC" "$DST" >>$LOG 2>&1 

if [ $? -ne 0 ] ; then
	# Synchronisation process did not exit cleanly.
	logger -t $PROG "Sync started, but did not complete"
	echo "Sync started, but did not complete" >>$LOG
else
	# Synchronisation process was successful. 
	logger -t $PROG "Backup of $SRC on $SERVERIP complete"
	echo `date +"%s"` >$BACKUPTIMESTAMP
	echo "Backup of $SRC on $SERVERIP complete" >>$LOG
fi

exit 0

# Adapted from the rsync script at Automated OSX backups with launchd and rsync-
# 
# This is the contents of the .backupignore file.
# 
# *@SynoResource
# @eaDir
# *.vsmeta
# .DS_Store
# .Spotlight-*/
# .Trashes
# .localized
# /afs/*
# /automount/*
# /cores/*
# /dev/*
# /Network/*
# /private/tmp/*
# /private/var/run/*
# /private/var/spool/postfix/*
# /private/var/vm/*
# /Previous Systems.localized
# /tmp/*
# /Volumes/*
# */.Trash
