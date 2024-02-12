#!/bin/bash

##############
## Settings ##
##############

# Set PATH/Locale
export LC_NUMERIC="en_US.UTF-8"
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ScriptPath=$(dirname "${BASH_SOURCE[0]}")

# Agent Version (do not change)
VERSION="1.0.0"

# SID (Server ID - automatically assigned on installation, do not change this)
# DO NOT share this ID with anyone
SID="SIDPLACEHOLDER"

# How frequently should the data be collected (do not modify this, unless instructed to do so)
CollectEveryXSeconds=3

# Runtime, in seconds (do not modify this, unless instructed to do so)
Runtime=60

# Network Interfaces
# * if you leave this setting empty our agent will detect and monitor all of your active network interfaces
# * if you wish to monitor just one interface, fill its name down below (ie: "eth1")
# * if you wish to monitor just some specific interfaces, fill their names below separated by comma (ie: "eth0,eth1,eth2")
NetworkInterfaces=""

################################################
## CAUTION: Do not edit any of the code below ##
################################################

# Function used to prepare base64 str for url encoding
function base64prep() {
	str=$1
	str="${str//+/%2B}"
	str="${str//\//%2F}"
	echo "$str"
}

# Kill any lingering agent processes
HTProcesses=$(pgrep -f webstatus_agent.sh | wc -l)
if [ -z "$HTProcesses" ]
then
	HTProcesses=0
fi
if [ "$HTProcesses" -gt 15 ]
then
	pgrep -f webstatus_agent.sh | xargs kill -9
fi
for PID in $(pgrep -f webstatus_agent.sh)
do
	PID_TIME=$(ps -p "$PID" -oetime= | tr '-' ':' | awk -F: '{total=0; m=1;} {for (i=0; i < NF; i++) {total += $(NF-i)*m; m *= i >= 2 ? 24 : 60 }} {print total}')
	if [ -n "$PID_TIME" ] && [ "$PID_TIME" -ge 120 ]
	then
		kill -9 "$PID"
	fi
done

# Calculate how many times per minute should the data be collected (based on the `CollectEveryXSeconds` setting)
RunTimes=$((Runtime / CollectEveryXSeconds))

# Start timers
START=$(date +%s)
tTIMEDIFF=0
M=$(date +%M | sed 's/^0*//')
if [ -z "$M" ]
then
	M=0
	# Clear the web_status.log every hour
	rm -f "$ScriptPath"/webstatus_cron.log
fi

# Network interfaces
if [ -n "$NetworkInterfaces" ]
then
	# Use the network interfaces specified in Settings
	IFS=',' read -r -a NetworkInterfacesArray <<< "$NetworkInterfaces"
else
	# Automatically detect the network interfaces
	NetworkInterfacesArray=()
    while IFS='' read -r line; do NetworkInterfacesArray+=("$line"); done < <(ip a | grep BROADCAST | grep 'state UP' | awk '{print $2}' | awk -F ":" '{print $1}' | awk -F "@" '{print $1}')
fi
# Get the initial network usage
T=$(cat /proc/net/dev)
declare -A aRX
declare -A aTX
declare -A tRX
declare -A tTX
# Loop through network interfaces
for NIC in "${NetworkInterfacesArray[@]}"
do
	aRX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $2}')
	aTX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $10}')
done

# Collect data loop
for X in $(seq $RunTimes)
do
	# Get vmstat info
	VMSTAT=$(vmstat $CollectEveryXSeconds 2 | tail -1)
	# Get CPU Load
	CPU=$(echo "$VMSTAT" | awk '{print 100 - $15}')
	tCPU=$(echo | awk "{print $tCPU + $CPU}")
	# Get IO Wait
	IOW=$(echo "$VMSTAT" | awk '{print $16}')
	tIOW=$(echo | awk "{print $tIOW + $IOW}")
	# Get RAM Usage
	aRAM=$(echo "$VMSTAT" | awk '{print $4 + $5 + $6}')
	bRAM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
	RAM=$(echo | awk "{print $aRAM * 100 / $bRAM}")
	RAM=$(echo | awk "{print 100 - $RAM}")
	tRAM=$(echo | awk "{print $tRAM + $RAM}")
	# Get Network Usage
	T=$(cat /proc/net/dev)
	END=$(date +%s)
	TIMEDIFF=$(echo | awk "{print $END - $START}")
	tTIMEDIFF=$(echo | awk "{print $tTIMEDIFF + $TIMEDIFF}")
	START=$(date +%s)
	# Loop through network interfaces
	for NIC in "${NetworkInterfacesArray[@]}"
	do
		# Received Traffic
		RX=$(echo | awk "{print $(echo "$T" | grep -w "$NIC:" | awk '{print $2}') - ${aRX[$NIC]}}")
		RX=$(echo | awk "{print $RX / $TIMEDIFF}")
		RX=$(echo "$RX" | awk '{printf "%18.0f",$1}' | xargs)
		aRX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $2}')
		tRX[$NIC]=$(echo | awk "{print ${tRX[$NIC]} + $RX}")
		tRX[$NIC]=$(echo "${tRX[$NIC]}" | awk '{printf "%18.0f",$1}' | xargs)
		# Transferred Traffic
		TX=$(echo | awk "{print $(echo "$T" | grep -w "$NIC:" | awk '{print $10}') - ${aTX[$NIC]}}")
		TX=$(echo | awk "{print $TX / $TIMEDIFF}")
		TX=$(echo "$TX" | awk '{printf "%18.0f",$1}' | xargs)
		aTX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $10}')
		tTX[$NIC]=$(echo | awk "{print ${tTX[$NIC]} + $TX}")
		tTX[$NIC]=$(echo "${tTX[$NIC]}" | awk '{printf "%18.0f",$1}' | xargs)
	done
 
	# Check if minute changed, so we can end the loop
	MM=$(date +%M | sed 's/^0*//')
	if [ -z "$MM" ]
	then
		MM=0
	fi
	if [ "$MM" -gt "$M" ] 
	then
		break
	fi
done

# Get Operating System and Kernel
# Check via lsb_release if possible
if command -v "lsb_release" > /dev/null 2>&1
then
	OS=$(lsb_release -s -d)
# Check if it's Debian
elif [ -f /etc/debian_version ]
then
	OS="Debian $(cat /etc/debian_version)"
# Check if it's CentOS/Fedora
elif [ -f /etc/redhat-release ]
then
	OS=$(cat /etc/redhat-release)
	# Check if system requires reboot (Only supported in CentOS/RHEL 7 and later, with yum-utils installed)
	if timeout -s 9 5 needs-restarting -r | grep -q 'Reboot is required'
	then
		RequiresReboot=1
	fi
# If all else fails, get Kernel name
else
	OS="$(uname -s) $(uname -r)"
fi

OS=$(echo -ne "$OS|$(uname -r)|$RequiresReboot" | base64)
# Get the server uptime
Uptime=$(awk '{print $1}' < /proc/uptime)
# Get CPU model
CPUModel=$(grep -m1 'model name' /proc/cpuinfo | awk -F": " '{print $2}')
CPUModel=$(echo -ne "$CPUModel" | base64)
# Get CPU speed (MHz)
CPUSpeed=$(grep -m1 'cpu MHz' /proc/cpuinfo | awk -F": " '{print $2}')
CPUSpeed=$(echo -ne "$CPUSpeed" | base64)
# Get number of cores
CPUCores=$(grep -c processor /proc/cpuinfo)
# Calculate average CPU Usage
CPU=$(echo | awk "{print $tCPU / $X}")
# Calculate IO Wait
IOW=$(echo | awk "{print $tIOW / $X}")
# Get system memory (RAM)
RAMSize=$(grep ^MemTotal: /proc/meminfo | awk '{print $2}')
# Calculate RAM Usage
RAM=$(echo | awk "{print $tRAM / $X}")
# Get the Swap Size
SwapSize=$(grep ^SwapTotal: /proc/meminfo | awk '{print $2}')
# Calculate Swap Usage
SwapFree=$(grep ^SwapFree: /proc/meminfo | awk '{print $2}')
if [ "$SwapSize" -gt 0 ]
then
	Swap=$(echo | awk "{print 100 - (($SwapFree / $SwapSize) * 100)}")
else
	Swap=0
fi

# Get all disks usage
DISKs=$(echo -ne "$(timeout 3 df -TPB1 | sed 1d | grep -v -E 'tmpfs' | awk '{print $(NF)","$3","$4","$5";"}')" | gzip -cf | base64)
DISKs=$(base64prep "$DISKs")
# Get all disks inodes
DISKi=$(echo -ne "$(timeout 3 df -Ti | sed 1d | grep -v -E 'tmpfs' | awk '{print $(NF)","$3","$4","$5";"}')" | gzip -cf | base64)
DISKi=$(base64prep "$DISKi")

# Calculate Total Network Usage (bytes)
RX=0
TX=0
for NIC in "${NetworkInterfacesArray[@]}"
do
	# Calculate individual NIC usage
	RX=$(echo | awk "{print ${tRX[$NIC]} / $X}")
	RX=$(echo "$RX" | awk '{printf "%18.0f",$1}' | xargs)
	TX=$(echo | awk "{print ${tTX[$NIC]} / $X}")
	TX=$(echo "$TX" | awk '{printf "%18.0f",$1}' | xargs)
done
NICS=$(echo -ne "$NICS" | gzip -cf | base64)
NICS=$(base64prep "$NICS")


# Prepare data
DATA="$OS|$Uptime|$CPUModel|$CPUSpeed|$CPUCores|$CPU|$IOW|$RAMSize|$RAM|$SwapSize|$Swap|$DISKs|$NICS|$CONN|$DISKi"
POST="v=$VERSION&s=$SID&d=$DATA"
# Save data to file
echo "$POST" > "$ScriptPath"/webstatus_agent.log

# Post data
wget --retry-connrefused --waitretry=1 -t 3 -T 15 -qO- --post-file="$ScriptPath/webstatus_agent.log" https://webstatus.dev/ &> /dev/null
