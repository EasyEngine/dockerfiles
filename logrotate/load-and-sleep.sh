
#!/bin/sh

set -x

#  copy the script logrotate-run.sh to the 15 minute crontab entry
cp /etc/logrotate.d/easyengine /etc/periodic/15min/
if [ $? -ne 0 ]; then
	  echo "copy command failed"
	    exit 1
    fi

    #start cron
    crond -f -d 2
