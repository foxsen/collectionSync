#!/bin/bash

### This script tries to create collections from documents directory, it will erase any existing collections
### Use at your own risk. Fuxin Zhang
clear_existing_collections() {
  delete_post_prefix='{"commands":[{"delete":{"uuid":"'
  delete_post_suffix='"}}],"type":"ChangeRequest","id":1}'
  sql="select p_uuid from Entries where p_type== 'Collection'";
  sqlite3 /var/local/cc.db "$sql" | while read u; do
    post_data=$delete_post_prefix$u$delete_post_suffix
#    echo "Deleting collection $u" $post_data 
    echo $post_data >> ./commands
#    /usr/java/bin/cvm PerformPost change $post_data
  done
}

insert_collection() {
  insert_post_data_prefix='{"commands":[{"insert":{"type":"Collection","uuid":"';
  insert_post_data_1='","lastAccess":';
  insert_post_data_2=',"titles":[{"display":"';
  insert_post_data_3='","direction":"LTR","language":"en-US"}],"isVisibleInHome":true}}],"type":"ChangeRequest","id":2}';
  
#  echo "inserting collection" $1
  uuid=`cat /proc/sys/kernel/random/uuid`
  post_data=$insert_post_data_prefix$uuid$insert_post_data_1`date +%s`$insert_post_data_2$1$insert_post_data_3;
    echo $post_data >> ./commands
#  /usr/java/bin/cvm PerformPost change $post_data
}

update_collection() {
   update_post_data_prefix='{"commands":[{"update":{"type":"Collection","uuid":"'
   update_post_data_1='","members":['
   update_post_data_2=']}}],"type":"ChangeRequest","id":7}'
#   echo "updating members for collection " $1 $2
   
   dir="/mnt/us/documents/"`echo "$1" | sed 's/－/\//g'`

   ##be careful for file name with spaces!
  post_data=$update_post_data_prefix$2$update_post_data_1
  n=0
  find "$dir" -maxdepth 1 -type f | while read f ; do
    sql="select p_uuid from Entries where p_location == '"$f"'";
    u=`sqlite3 /var/local/cc.db "$sql"`;
    if test $u; then  
      ##echo "add uuid $u"
      n=$((n+1))
      if  [ $n -gt 1 ] ; then
        member_data=$member_data\,\"$u\"
      else
        member_data=\"$u\"
      fi
    else
      echo "Warning:$f is not in the Entries database, will be ignored!" >> ./log
      echo "Warning:Either it is not in a format recognized by kindle, or you have not waited kindle to finish the scan? If so retry later." >> ./log
    fi
    echo $member_data > /tmp/member_data
  done 
  post_data=$post_data`cat /tmp/member_data`$update_post_data_2
#  echo "updating collection" $1 $post_data
    echo $post_data >> ./commands
#  /usr/java/bin/cvm PerformPost change $post_data
}

create_collections() {

##find all dirs, remove prefix /mnt/us/documents/, replace '/' to '－', filter out .sdr files(used by kindle), empty lines, and /mnt/us/documents itself
  find /mnt/us/documents -type d | sed "s/^\/mnt\/us\/documents\///g" | sed "s/\//－/g" | grep -v "\.sdr$" | \
    grep -v "^$" | grep -v "－mnt－us－documents" | while read dir; do

    realdir="/mnt/us/documents/"`echo "$dir" | sed 's/－/\//g'`
    filecount=`find "$realdir" -maxdepth 1 -type f | wc -l`
  
    ##echo $dir,$realdir,$filecount
    if [ $filecount -gt 0 ] ; then
      insert_collection "$dir"
      update_collection "$dir" $uuid
    fi
  done
}

cd /mnt/us/extensions/collectionSync
rm -f ./commands
rm -f ./log
touch ./commands

### enter screensaver mode to tell user work start
lipc-set-prop com.lab126.powerd preventScreenSaver 0
lipc-set-prop com.lab126.powerd powerButton 1
lipc-set-prop com.lab126.powerd preventScreenSaver 1

scan_done=`lipc-get-prop com.lab126.scanner fullScanStatus`
if [ $scan_done -ne 0 ] ; then
  echo "Kindle scanner has not finished scanned all books, Waiting start at date" `date` >> ./log
  lipc-probe -v com.lab126.scanner >> ./log
fi
times=0
while [ $scan_done -ne 0 ] ; do
  scan_done=`lipc-get-prop com.lab126.scanner fullScanStatus`
  sleep 3
  lipc-set-prop com.lab126.powerd preventScreenSaver 0
  lipc-set-prop com.lab126.powerd powerButton 1
  lipc-set-prop com.lab126.powerd preventScreenSaver 1
  times=$((times+1))
  if [ $times -gt 1000 ] ; then
    echo "Wait for too long a time, quit..." >> ./log
  fi
done
echo "Started at " `date` >> ./log

### pause indexer
lipc-set-prop com.lab126.indexer pauseIndexerMilliseconds 6000000
sleep 1

### first of all, delete all existing collections
clear_existing_collections 

### then find out all directories that have >=1 regular files
### create a collection and fill in items
create_collections

lipc-set-prop com.lab126.powerd preventScreenSaver 0
lipc-set-prop com.lab126.powerd powerButton 1
lipc-set-prop com.lab126.powerd preventScreenSaver 1

/usr/java/bin/cvm PerformPostBatch
if [ $? -ne 0 ]; then
  echo "Something goes wrong, dump the log"
  showlog >>  ./log
else
  echo "Successfully done." >> ./log
fi
#rm -f ./commands

### let indexer continue
lipc-set-prop com.lab126.indexer pauseIndexerMilliseconds 0

### enter screensaver mode to tell user work done
lipc-set-prop com.lab126.powerd preventScreenSaver 0
lipc-set-prop com.lab126.powerd powerButton 1
