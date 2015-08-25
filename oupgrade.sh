#!/bin/sh

#DBG. /usr/share/libubox/jshn.sh  

# setup variables
FIRMWARE_FILE="firmware.json"

#LOCAL_PATH="/etc/onion/config"
LOCAL_PATH="."
LOCAL_FILE="$LOCAL_PATH/$FIRMWARE_FILE"

TMP_PATH="/tmp"


bUsage=0
bVersionOnly=0
bUbusOutput=0
bUpgrade=0

# read arguments
while [ "$1" != "" ]
do
	case "$1" in
    	-v|-version|--version)
			bVersionOnly=1
	    ;;
	    -h|-help|--help)
			bUsage=1
	    ;;
	    -u|-ubus)
			bUbusOutput=1
	    ;;
	    *)
			echo "ERROR: Invalid Argument"
			echo ""
			bUsage=1
	    ;;
	esac

	shift
done


################################
##### Functions
PrintUsage () {
	echo "Functionality:"
	echo "	Check if new Onion firmware is available and perform upgrade"
	echo ""
	echo "Usage: $0"
	echo ""
	echo "Arguments:"
	echo "	-v 		Just print the current firmware version"
	echo "	-u 		Script output is ubus compatible"
	echo "	-h 		Print this usage prompt"
	echo ""
}


################################


# print the script usage
if [ $bUsage == 1 ]
then
	PrintUsage
	exit
fi


## get the current version
json_load "$(cat $LOCAL_FILE)"
json_get_var currentVersion version

if [ $bUbusOutput == 0 ]; then
	echo "> Device Firmware Version: $currentVersion"
fi

# optional exit after checking device firmware version
if [ $bVersionOnly == 1 ]
then
	if [ $bUbusOutput == 1 ]; then
		echo "{\"version\":$currentVersion}"
	fi

	exit
fi


## get the latest repo version
json_get_var REMOTE_URL url
REPO_FILE="$REMOTE_URL/$FIRMWARE_FILE"
REMOTE_JSON="$(wget -O - $REMOTE_FILE)"

json_load "$REMOTE_JSON"
json_get_var repoVersion version

if [ $bUbusOutput == 0 ]; then
	echo "> Repo Firmware Version: $currentVersion"
fi


## compare the versions
if [ $currentVersion != $remoteVersion ]; then
	if [ $bUbusOutput == 0 ]; then
		echo "> New firmware available, need to upgrade device firmware"
		bUpgrade=1
	fi
else
	if [ $bUbusOutput == 0 ]; then
		echo "> Device firmware is up to date!"
	fi
fi


## perform the firmware upgrade
if [ $bUpgrade == 1 ]; then
	# download the new firmware
	if [ $bUbusOutput == 0 ]; then
		echo "> Downloading new firmware..."
	fi

	json_get_var BINARY bin
	REPO_BIN="$REMOTE_URL/$BINARY"

	wget -q -0 $TMP_PATH "$REPO_BIN"

	# start firmware upgrade
	if [ $bUbusOutput == 0 ]; then
		echo "> Starting firmware upgrade...."
	else
		echo "{\"upgrade\":true}"
	fi

	LOCAL_BIN="$TMP_PATH/$BIN"
	sysupgrade $LOCAL_BIN &
else
	if [ $bUbusOutput == 1 ]; then
		echo "{\"upgrade\":false}"
	fi
fi





