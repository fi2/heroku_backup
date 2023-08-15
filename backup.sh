#!/bin/bash

if [ -z "$HEROKU_API_KEY" ]; then
    echo "HEROKU_API_KEY is not set. Please set it as an environment variable."
    exit 1
fi

apps=(app1 app2 app3)
EMAIL="youremail@example.com"
DATE=`date +%Y-%m-%d`
BACKUP_DIR="/media/username/MySSD/my-heroku-backups"
LOG_FILE="${BACKUP_DIR}/backup_log_${DATE}.txt"

function log_message {
   echo "$1" | tee -a $LOG_FILE
}

# Check if pg_restore is available, which will be used for basic validation of the dump file
if ! command -v pg_restore &> /dev/null; then
    PG_RESTORE_AVAILABLE=false
else
    PG_RESTORE_AVAILABLE=true
fi

# Backup each application
for i in ${apps[@]}; do
   log_message "=============== APP: ${i} =============="

   mkdir -p "${BACKUP_DIR}/${i}/${DATE}"

   # 1. Create heroku backup

   heroku pg:backups:capture --app ${i}
   if [ $? -ne 0 ]; then
       log_message "Backup for ${i} failed"
       echo "Backup for ${i} failed" | mail -s "[FAILED-BACKUP!] Backup Failed for ${i}" $EMAIL
       continue
   fi

   log_message "Backup for ${i} was successful"
   echo "Backup for ${i} was successful" | mail -s "[SUCCESS] Backup Successful for ${i}" $EMAIL

   # 2. Download the backup dump file 

   url=$(heroku pg:backups:url --app ${i})
   wget -O ${BACKUP_DIR}/${i}/${DATE}/backup.dump $url
   if [ $? -ne 0 ]; then
       log_message "Failed to download backup for ${i}"
       continue
   fi

   # 3. Basic backup validation
   if $PG_RESTORE_AVAILABLE; then  
     pg_restore --list ${BACKUP_DIR}/${i}/${DATE}/backup.dump > /dev/null 2>&1
     if [ $? -ne 0 ]; then
       log_message "Backup dump validation failed for ${i}"
       echo "Backup dump validation failed for ${i}" | mail -s "Backup Dump Validation Failed for ${i}" $EMAIL
     fi
   else 
     log_message "pg_restore is not available. skipping validation"
   fi

   gzip -f ${BACKUP_DIR}/${i}/${DATE}/backup.dump
done

# Purge backups older than 60 days
find "${BACKUP_DIR}" -type d -mtime +60 -exec rm -rf {} +
log_message "Purged backups older than 60 days"
