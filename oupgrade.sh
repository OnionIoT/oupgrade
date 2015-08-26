#!/bin/sh

. /usr/share/libubox/jshn.sh  

# setup variables
FIRMWARE_FILE="firmware.json"

LOCAL_PATH="/etc/onion/"
#LOCAL_PATH="."
LOCAL_FILE="$LOCAL_PATH/$FIRMWARE_FILE"

TMP_PATH="/tmp"

REPO_URL="http://cloud.onion.io/api/firmware"
STABLE_FILE="stable.json"
LATEST_FILE="latest.json"


bUsage=0
bVersionOnly=0
bUbusOutput=0
bUpgrade=0
bLatest=0



# read arguments
while [ "$1" != "" ]
do
	case "$1" in
    	-h|-help|--help)
			bUsage=1
	    ;;
    	-v|-version|--version)
			bVersionOnly=1
	    ;;
	    -l|-latest|--latest)
			bLatest=1
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
	echo "	-help 		Print this usage prompt"
	echo "	-version 	Just print the current firmware version"
	echo "	-latest 	Use latest repo version (instead of stable version)"
	echo "	-ubus 	Script output is ubus compatible"
	
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
if [ $bUbusOutput == 0 ]; then
	echo "> Checking latest version online..."
fi

# find the remote version file to be used
if [ $bLatest == 0 ]; then
	# use the stable version
	REPO_FILE="$REPO_URL/$STABLE_FILE"
else
	# use the latest version
	REPO_FILE="$REPO_URL/$LATEST_FILE"
fi

# read the json
TMP_JSON="$TMP_PATH/tmp.json"
CMD="rm -rf $TMP_JSON"
eval $CMD

CMD="wget -q -O $TMP_JSON \"$REPO_FILE\""

while [ ! -f $TMP_JSON ]
do
	eval $CMD
done

REMOTE_JSON="$(cat $TMP_JSON)"

json_load "$REMOTE_JSON"
json_get_var repoVersion version

if [ $bUbusOutput == 0 ]; then
	echo "> Repo Firmware Version: $repoVersion"
fi


## compare the versions
if [ "$currentVersion" != "$remoteVersion" ]; then
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

	json_get_var REPO_BINARY url

	BINARY=${REPO_BINARY##*/}
	LOCAL_BIN="$TMP_PATH/$BINARY"
	
	if [ -f $LOCAL_BIN ]; then
		eval rm -rf $LOCAL_BIN
	fi

	while [ ! -f $LOCAL_BIN ]
	do
		wget -O $LOCAL_BIN "$REPO_BINARY"
	done

	# start firmware upgrade
	if [ $bUbusOutput == 0 ]; then
		echo "> Starting firmware upgrade...."
	else
		echo "{\"upgrade\":true}"
	fi

	#sysupgrade $LOCAL_BIN &
else
	if [ $bUbusOutput == 1 ]; then
		echo "{\"upgrade\":false}"
	fi
fi





