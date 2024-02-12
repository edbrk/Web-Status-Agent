#!/bin/bash

# Set PATH
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Check if install script is run by root
echo "Checking root privileges..."
if [ "$EUID" -ne 0 ]
  then echo "Please run the install script as root."
  exit
fi
echo "... done."

# Fetch Server Unique ID
SID=$1

# Remove old agent (if exists)
echo "Checking if webstatus agent folder exists..."
if [ -d /etc/webstatus ]
then
	echo "Old webstatus agent found, deleting it..."
	rm -rf /etc/webstatus
else
	echo "No old webstatus agent folder found..."
fi
echo "... done."

# Killing any running webstatus agents
echo "Killing any webstatus agent scripts that may be currently running..."
ps aux | grep -ie webstatus_agent.sh | awk '{print $2}' | xargs kill -9
echo "... done."

# Removing cronjob (if exists)
echo "Removing any hetrixtools cronjob, if exists..."
crontab -u root -l | grep -v 'webstatus_agent.sh'  | crontab -u root - >/dev/null 2>&1
crontab -u webstatus -l | grep -v 'webstatus_agent.sh'  | crontab -u webstatus - >/dev/null 2>&1
echo "... done."

# Cleaning up uninstall file
echo "Cleaning up the installation file..."
if [ -f $0 ]
then
    rm -f $0
fi
echo "... done."

# Let webstatus platform know uninstall has been completed
echo "Letting webstatus platform know the uninstallation has been completed..."
POST="v=uninstall&s=$SID"
wget -t 1 -T 30 -qO- --post-data "$POST" https://sm.hetrixtools.net/ &> /dev/null
echo "... done."

# All done
echo "webstatus agent uninstallation completed."
