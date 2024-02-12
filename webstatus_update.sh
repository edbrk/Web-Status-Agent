#!/bin/bash

# Set PATH
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Old Agent Path
AGENT="/etc/webstatus/webstatus_agent.sh"

# Check if user specified version to update to
if [ -z "$1" ]
then
	VERS="master"
else
	VERS=$1
fi

# Check if install script is run by root
echo "Checking root privileges..."
if [ "$EUID" -ne 0 ]
  then echo "ERROR: Please run the install script as root."
  exit
fi
echo "... done."

# Check if system has crontab and wget
echo "Checking for crontab and wget..."
command -v crontab >/dev/null 2>&1 || { echo "ERROR: Crontab is required to run this agent." >&2; exit 1; }
command -v wget >/dev/null 2>&1 || { echo "ERROR: wget is required to run this agent." >&2; exit 1; }
echo "... done."

# Look for the old agent
echo "Looking for the old agent..."
if [ -f "$AGENT" ]
then
	echo "... done."
else
	echo "ERROR: No old agent found. Nothing to update." >&2; exit 1;
fi

# Extract data from the old agent
echo "Extracting configs from the old agent..."
# SID (Server ID)
SID=$(grep 'SID="' $AGENT | awk -F'"' '{ print $2 }')
echo "... done."

# Fetching new agent
echo "Fetching the new agent..."
wget -t 1 -T 30 -qO $AGENT https://raw.githubusercontent.com/edbrk/agent/$VERS/webstatus_agent.sh
echo "... done."

# Inserting Server ID (SID) into the agent config
echo "Inserting Server ID (SID) into agent config..."
sed -i "s/SIDPLACEHOLDER/$SID/" $AGENT
echo "... done."

# Killing any running hetrixtools agents
echo "Making sure no Web Status agent scripts are currently running..."
ps aux | grep -ie webstatus_agent.sh | awk '{print $2}' | xargs kill -9
echo "... done."

# Cleaning up install file
echo "Cleaning up the update file..."
if [ -f $0 ]
then
    rm -f $0
fi
echo "... done."

# All done
echo "WebStatus agent update completed. It can take up to two (2) minutes for new data to be collected."
