#!/bin/bash
#
# Version - changes - author
#1.0 - Initial - dkupch
# What is still missing:
# Check for sudoers access to run this script
# Check for OS
# Check for drives with the same size and Media
#
set -o errexit
set -o nounset
set -o xtrace

#
#
# 
# --- Start MAAS 1.0 script metadata ---
# name: 00-create-MegaRAID_RAID10
# description: This Script creates RAID10 across all available disks
# parallel: disabled
# script_type: commissioning
# timeout: 30
# --- End MAAS 1.0 script metadata ---

#Variables
Disks=()
Slots=()
Arrays=()
declare -i NumOfDisks

# Download and install LSI MegaRAID Megacli
if lspci | grep -q MegaRAID
then 
echo "MegaRAID Controller found will check for Virtual Drives"
FILE=megacli_8.07.14-2_all.deb
URL=""
if [ ! -f $FILE ]; then
	wget $URL/$FILE || { echo 'Unable to get megacli pkg' ; exit 1; }
	sudo dpkg -i *megacli*.deb
fi

#
# Create RAID10 if no Arrays configured on the controller. 
# In case RAID array already exist, the script will fail and the administrator would have to figure out the rest.
#

 if sudo /opt/MegaRAID/MegaCli/MegaCli64 -LDInfo -LAll -a0 | grep -q "No Virtual Drive Configured"
 then
 echo "Will continue to create Volumes"
	 DEVICEID=$(sudo /opt/MegaRAID/MegaCli/MegaCli64 -EncInfo -aALL | grep "Device ID" | rev | cut -d " " -f1 | rev)
	 echo ENC: $DEVICEID
	 for SLOTNUMBER in $(sudo /opt/MegaRAID/MegaCli/MegaCli64 -PDList -aALL  | grep "Slot Number" | awk -F: '{print $2}')
	 do 
	 #echo DISK: $SLOTNUMBER
	 Disks+=( "[$DEVICEID:$SLOTNUMBER]" )
	 Slots+=( "$SLOTNUMBER" )
	 NumOfDisks+=1
	 done
	 echo Slots: ${Slots[@]}
	 echo "Number of Disks: $NumOfDisks"
	 if [ "${NumOfDisks}" > 0 ] && [ $(( "${NumOfDisks}" % 2 )) = 0 ]; then 
	#	 echo SLOTS:${#Slots[@]}
		 for ((i=0; i<${#Slots[@]}; i+=2)); do
	#		 echo "${Slots[$i]}" ${Slots[$i+1]}
			 Arrays+=( -Array$i[$DEVICEID:${Slots[$i]},$DEVICEID:${Slots[$i+1]}])
	 	 done
		# Move two last disks of the Array to a HotSpare mode
		 #echo ${Arrays[@]}
		 #echo ${Arrays[-1]} | sed -r 's/-Array[0-9]+//g'
		 echo "Locating last two drives to allocate the Spares..."
		 HotSpares=$(echo "${Arrays[-1]}" | sed -r 's/-Array[0-9]+//g')
		 echo "Hot Spare Drives: $HotSpares"
		# Exluding last two disks from Array
		 unset Arrays[${#Arrays[@]}-1]
		 #echo ${Arrays[@]}
		# Configure HotSpares
		 sudo /opt/MegaRAID/MegaCli/MegaCli64 -PDMakeGood -PhysDrv "$HotSpares" -Force -a0
		 sudo /opt/MegaRAID/MegaCli/MegaCli64 -PDHSP -Set -PhysDrv "$HotSpares" -a0
		# Create RAID10 Array ACTION
		 sudo /opt/MegaRAID/MegaCli/MegaCli64 -CfgSpanAdd -R10 ${Arrays[@]} -a0
	 else
		 echo "WARNING: Unable to create a RAID array either zero or odd number of disks available"
		 echo "Exitting..."
		 exit 1
	 fi
	 else
	 echo "At least one Virtual Drive found, Skipping"
 fi
else 
echo "MegaRAID Controller not found, nothing to see here"; exit
fi
