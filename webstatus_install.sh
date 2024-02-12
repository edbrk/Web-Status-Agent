#!/bin/bash

# Set PATH
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Check if install script is run by root
echo "Checking root privileges..."
if [ "$EUID" -ne 0 ]
  then echo "ERROR: Please run the install script as root."
  exit
fi
echo "... done."

# Fetch Server Unique ID
SID=$1

# Make sure SID is not empty
echo "Checking Server ID (SID)..."
if [ -z "$SID" ]
	then echo "ERROR: First parameter missing."
	exit
fi
echo "... done."

# Check if system has crontab and wget
echo "Checking for crontab and wget..."
command -v crontab >/dev/null 2>&1 || { echo "ERROR: Crontab is required to run this agent." >&2; exit 1; }
command -v wget >/dev/null 2>&1 || { echo "ERROR: wget is required to run this agent." >&2; exit 1; }
echo "... done."

# Remove old agent (if exists)
echo "Checking if there's any old webstatus agent already installed..."
if [ -d /etc/webstatus ]
then
	echo "Old webstatus agent found, deleting it..."
	rm -rf /etc/webstatus
else
	echo "No old webstatus agent found..."
fi
echo "... done."

# Creating agent folder
echo "Creating the webstatus agent folder..."
mkdir -p /etc/webstatus
echo "... done."

# Fetching new agent
echo "Fetching the new agent..."
wget -t 1 -T 30 -qO /etc/webstatus/webstatus_agent.sh https://raw.githubusercontent.com/edbrk/web-status-agent/master/webstatus_agent.sh
echo "... done."

# Inserting Server ID (SID) into the agent config
echo "Inserting Server ID (SID) into agent config..."
sed -i "s/SIDPLACEHOLDER/$SID/" /etc/webstatus/webstatus_agent.sh
echo "... done."

# Killing any running webstatus agents
echo "Making sure no webstatus agent scripts are currently running..."
ps aux | grep -ie webstatus_agent.sh | awk '{print $2}' | xargs kill -9
echo "... done."

# Removing old cronjob (if exists)
echo "Removing any old webstatus cronjob, if exists..."
crontab -u root -l | grep -v 'webstatus_agent.sh'  | crontab -u root - >/dev/null 2>&1
crontab -u webstatus -l | grep -v 'webstatus_agent.sh'  | crontab -u webstatus - >/dev/null 2>&1
echo "... done."


echo "Setting up the new cronjob as 'root' user..."
crontab -u root -l 2>/dev/null | { cat; echo "* * * * * bash /etc/webstatus/webstatus_agent.sh >> /etc/webstatus/webstatus_cron.log 2>&1"; } | crontab -u root - >/dev/null 2>&1

echo "... done."

# Cleaning up install file
echo "Cleaning up the installation file..."
if [ -f $0 ]
then
    rm -f $0
fi
echo "... done."

# Let webstatus platform know install has been completed
echo "Letting webstatus platform know the installation has been completed..."
curl -X PATCH "http://localhost/api/server-agent/install/${SID}" -d "" -s -o /dev/null 
echo "... done."

# Start the agent
echo "Starting the agent under the 'root' user..."
bash /etc/webstatus/webstatus_agent.sh > /dev/null 2>&1 &

echo "... done."

# All done
echo "webstatus agent installation completed."
