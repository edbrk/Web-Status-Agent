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

# Check if user has selected to run agent as 'root' or as 'webstatus' user
if [ -z "$2" ]
	then echo "ERROR: Second parameter missing."
	exit
fi

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
wget -t 1 -T 30 -qO /etc/webstatus/webstatus_agent.sh https://raw.githubusercontent.com/webstatus/agent/master/webstatus_agent.sh
echo "... done."

# Inserting Server ID (SID) into the agent config
echo "Inserting Server ID (SID) into agent config..."
sed -i "s/SIDPLACEHOLDER/$SID/" /etc/webstatus/webstatus_agent.sh
echo "... done."

# Check if any services are to be monitored
echo "Checking if any services should be monitored..."
if [ "$3" != "0" ]
then
	echo "Services found, inserting them into the agent config..."
	sed -i "s/CheckServices=\"\"/CheckServices=\"$3\"/" /etc/webstatus/webstatus_agent.sh
fi
echo "... done."

# Check if software RAID should be monitored
echo "Checking if software RAID should be monitored..."
if [ "$4" -eq "1" ]
then
	echo "Enabling software RAID monitoring in the agent config..."
	sed -i "s/CheckSoftRAID=0/CheckSoftRAID=1/" /etc/webstatus/webstatus_agent.sh
fi
echo "... done."

# Check if Drive Health should be monitored
echo "Checking if Drive Health should be monitored..."
if [ "$5" -eq "1" ]
then
	echo "Enabling Drive Health monitoring in the agent config..."
	sed -i "s/CheckDriveHealth=0/CheckDriveHealth=1/" /etc/webstatus/webstatus_agent.sh
fi
echo "... done."

# Check if 'View running processes' should be enabled
echo "Checking if 'View running processes' should be enabled..."
if [ "$6" -eq "1" ]
then
	echo "Enabling 'View running processes' in the agent config..."
	sed -i "s/RunningProcesses=0/RunningProcesses=1/" /etc/webstatus/webstatus_agent.sh
fi
echo "... done."

# Check if any ports to monitor number of connections on
echo "Checking if any ports to monitor number of connections on..."
if [ "$7" != "0" ]
then
	echo "Ports found, inserting them into the agent config..."
	sed -i "s/ConnectionPorts=\"\"/ConnectionPorts=\"$7\"/" /etc/webstatus/webstatus_agent.sh
fi
echo "... done."

# Killing any running webstatus agents
echo "Making sure no webstatus agent scripts are currently running..."
ps aux | grep -ie webstatus_agent.sh | awk '{print $2}' | xargs kill -9
echo "... done."

# Checking if webstatus user exists
echo "Checking if webstatus user already exists..."
if id -u webstatus >/dev/null 2>&1
then
	echo "The webstatus user already exists, killing its processes..."
	pkill -9 -u `id -u webstatus`
	echo "Deleting webstatus user..."
	userdel webstatus
	echo "Creating the new webstatus user..."
	useradd webstatus -r -d /etc/webstatus -s /bin/false
	echo "Assigning permissions for the webstatus user..."
	chown -R webstatus:webstatus /etc/webstatus
	chmod -R 700 /etc/webstatus
else
	echo "The webstatus user doesn't exist, creating it now..."
	useradd webstatus -r -d /etc/webstatus -s /bin/false
	echo "Assigning permissions for the webstatus user..."
	chown -R webstatus:webstatus /etc/webstatus
	chmod -R 700 /etc/webstatus
fi
echo "... done."

# Removing old cronjob (if exists)
echo "Removing any old webstatus cronjob, if exists..."
crontab -u root -l | grep -v 'webstatus_agent.sh'  | crontab -u root - >/dev/null 2>&1
crontab -u webstatus -l | grep -v 'webstatus_agent.sh'  | crontab -u webstatus - >/dev/null 2>&1
echo "... done."

# Setup the new cronjob to run the agent either as 'root' or as 'webstatus' user, depending on client's installation choice.
# Default is running the agent as 'webstatus' user, unless chosen otherwise by the client when fetching the installation code from the webstatus website.
if [ "$2" -eq "1" ]
then
	echo "Setting up the new cronjob as 'root' user..."
	crontab -u root -l 2>/dev/null | { cat; echo "* * * * * bash /etc/webstatus/webstatus_agent.sh >> /etc/webstatus/webstatus_cron.log 2>&1"; } | crontab -u root - >/dev/null 2>&1
else
	echo "Setting up the new cronjob as 'webstatus' user..."
	crontab -u webstatus -l 2>/dev/null | { cat; echo "* * * * * bash /etc/webstatus/webstatus_agent.sh >> /etc/webstatus/webstatus_cron.log 2>&1"; } | crontab -u webstatus - >/dev/null 2>&1
fi
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
POST="v=install&s=$SID"
wget -t 1 -T 30 -qO- --post-data "$POST" https://webstatus.dev/ &> /dev/null
echo "... done."

# Start the agent
if [ "$2" -eq "1" ]
then
	echo "Starting the agent under the 'root' user..."
	bash /etc/webstatus/webstatus_agent.sh > /dev/null 2>&1 &
else
	echo "Starting the agent under the 'webstatus' user..."
	sudo -u webstatus bash /etc/webstatus/webstatus_agent.sh > /dev/null 2>&1 &
fi
echo "... done."

# All done
echo "webstatus agent installation completed."
