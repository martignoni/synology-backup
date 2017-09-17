# Synology backup

## A script to backup files on a Synology NAS

This script should be placed on the NAS and scheduled to run every hour. It checks if a backup has completed before several (configurable) hours and if this is not the case, it proceeds to do an effective backup. It checks also if the machine to backup is online and tries to wake it up.

Requires rsync 3 on machine to backup.

Source: https://github.com/martignoni/synology-backup
