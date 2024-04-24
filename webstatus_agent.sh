#!/bin/bash

# Settings
export LC_NUMERIC="en_US.UTF-8"
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ScriptPath=$(dirname "${BASH_SOURCE[0]}")

# Agent Version
VERSION="1.0.0"

# SID (Server ID)
SID="SIDPLACEHOLDER"

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
else
        OS="$(uname -s) $(uname -r)"
fi

# Automatically detect active network interfaces
NetworkInterfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo")

# Initialize variables
declare -A initialRX initialTX

# Get initial network stats
for iface in $NetworkInterfaces; do
    initialRX[$iface]=$(cat /sys/class/net/"$iface"/statistics/rx_bytes)
    initialTX[$iface]=$(cat /sys/class/net/"$iface"/statistics/tx_bytes)
done

# Collect system metrics
OS=$(echo -ne "$OS|$(uname -r)")
Uptime=$(awk '{print int($1)}' /proc/uptime)
CPUModel=$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo)
CPUSpeed=$(awk -F': ' '/cpu MHz/ {print int($2); exit}' /proc/cpuinfo)
CPUCores=$(grep -c processor /proc/cpuinfo)
CPUUsage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
IOWait=$(top -bn1 | grep "Cpu(s)" | awk '{print $6}')
RAMSize=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
RAMUsage=$(free | awk '/Mem:/ {print $3/$2 * 100.0}')
SwapSize=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
SwapUsage=$(free | awk '/Swap:/ {print $3/$2 * 100.0}')

# Disk usage
TotalDiskSize=$(df -B1 | awk '{if (NR!=1) sum+=$2} END {print sum}')
TotalDiskUsage=$(df -B1 | awk '{if (NR!=1) sum+=$3} END {print sum}')

# Calculate network usage
declare -A finalRX finalTX
for iface in $NetworkInterfaces; do
    finalRX[$iface]=$(cat /sys/class/net/"$iface"/statistics/rx_bytes)
    finalTX[$iface]=$(cat /sys/class/net/"$iface"/statistics/tx_bytes)
done

TotalRX=0
TotalTX=0
for iface in $NetworkInterfaces; do
    TotalRX=$((TotalRX + finalRX[$iface] - initialRX[$iface]))
    TotalTX=$((TotalTX + finalTX[$iface] - initialTX[$iface]))
done

# Compile the data into JSON
jsonData=$(jq -n \
                  --arg os "$OS" \
                  --arg uptime "$Uptime" \
                  --arg cpuModel "$CPUModel" \
                  --arg cpuSpeed "$CPUSpeed" \
                  --arg cpuCores "$CPUCores" \
                  --arg cpuUsage "$CPUUsage" \
                  --arg ioWait "$IOWait" \
                  --arg ramSize "$RAMSize" \
                  --arg ramUsage "$RAMUsage" \
                  --arg swapSize "$SwapSize" \
                  --arg swapUsage "$SwapUsage" \
                  --arg totalDiskSize "$TotalDiskSize" \
                  --arg totalDiskUsage "$TotalDiskUsage" \
                  --arg totalRX "$TotalRX" \
                  --arg totalTX "$TotalTX" \
                  '{os: $os, uptime: $uptime, cpuModel: $cpuModel, cpuSpeed: $cpuSpeed, cpuCores: $cpuCores, cpuUsage: $cpuUsage, ioWait: $ioWait, ramSize: $ramSize, ramUsage: $ramUsage, swapSize: $swapSize, swapUsage: $swapUsage, totalDiskSize: $totalDiskSize, totalDiskUsage: $totalDiskUsage, totalRX: $totalRX, totalTX: $totalTX}')

# Save JSON to a file
echo "$jsonData" > "$ScriptPath"/server_stats.json

# Post data using wget
URL="http://status.edbrook.site/api/server-agent/metrics/$SID"
wget --retry-connrefused --waitretry=1 -t 3 -T 15 --header="Content-Type: application/json" --post-data "$jsonData" "$URL" &> "$ScriptPath/response.log"

echo "Data posted to $URL"
