#!/bin/sh

. /usr/share/libubox/jshn.sh  

# setup variables
bUsage=0
bDeviceVersion=1
bRepoVersion=1
bCheck=1
bLatest=0
bUpgrade=0
bJsonOutput=0
bCheckOnly=0

deviceVersion=""
deviceVersionMajor=""
deviceVersionMinor=""
deviceVersionRev=""

repoVersion=""
repoVersionMajor=""
repoVersionMinor=""
repoVersionRev=""

repoBinary=""
binaryName=""


tmpPath="/tmp"
repoUrl="http://cloud.onion.io/api/firmware"
repoStableFile="stable.json"
repoLatestFile="latest.json"
timeout=500




# function to print script usage
Usage () {
	echo "Functionality:"
	echo "	Check if new Onion firmware is available and perform upgrade"
	echo ""
	echo "Usage: $0"
	echo ""
	echo "Arguments:"
	echo " -help 		Print this usage prompt"
	echo " -version 	Just print the current firmware version"
	echo " -latest 	Use latest repo version (instead of stable version)"
	echo " -force		Force the upgrade, regardless of versions"
	echo " -check 	Only compare versions, do not actually update"
	echo " -ubus 		Script outputs only json"
	
	echo ""
}

## functions to parse version data
# parsing (x).y.z
GetVersionMajor () {
	ret=${1%%.*}
	echo "$ret"
}

# parsing x.(y).z
GetVersionMinor () {
	tmp=${1#*.}
	ret=${tmp%%.*}
	echo "$ret"
}

# parsing x.y.(z)
GetVersionRevision () {
	ret=${1##*.}
	echo "$ret"
}

# function to read device firmware version
GetDeviceVersion () {
	local ver=$(uci -q get onion.@onion[0].version)
	if [ "$ver" != "" ]; then
		# read the device version
		deviceVersion=$ver

		# read the sub-version info
		deviceVersionMajor=$(GetVersionMajor "$deviceVersion")
		deviceVersionMinor=$(GetVersionMinor "$deviceVersion")
		deviceVersionRev=$(GetVersionRevision "$deviceVersion")
	else
		deviceVersion="unknown"
	fi
}

# function to read latest repo version
GetRepoVersion () {
	# define the file to write to 
	local tmpFile="$tmpPath/check.txt"
	local tmpJson="$tmpPath/ver.json"
	local rmCmd="rm -rf $tmpJson"
	eval $rmCmd

	#define the wget commands
	local wgetSpiderCmd="wget -t $timeout --spider -o $tmpFile \"$repoFile\""
	local wgetCmd="wget -t $timeout -q -O $tmpJson \"$repoFile\""

	# check the repo file exists
	local count=0
	local bLoop=1
	while 	[ $bLoop == 1 ];
	do
		eval $wgetSpiderCmd

		# read the response
		local readback=$(cat $tmpFile | grep "Remote file exists.")
		if [ "$readback" != "" ]; then
			bLoop=0
		fi

		# implement time-out
		count=`expr $count + 1`
		if [ $count -gt $timeout ]; then
			bLoop=0
			if [ $bJsonOutput == 0 ]; then
				echo "> ERROR: request timeout, internet connection not successful"
			fi

			exit
		fi
	done

	# fetch the file
	while [ ! -f $tmpJson ]
	do
		eval $wgetCmd
	done

	# parse the json file
	local RESP="$(cat $tmpJson)"
	json_load "$RESP"

	# check the json file contents
	json_get_var repoVersion version

	repoVersionMajor=$(GetVersionMajor "$repoVersion")
	repoVersionMinor=$(GetVersionMinor "$repoVersion")
	repoVersionRev=$(GetVersionRevision "$repoVersion")

	# parse the binary url
	json_get_var repoBinary url
	binaryName=${repoBinary##*/}

	localBinary="$tmpPath/$binaryName"
}

# function to add version info to json
JsonAddVersion () {
	json_add_object "$1"
		
	json_add_string "version" "$2"
	json_add_string "major" "$3"
	json_add_string "minor" "$4"
	json_add_string "revision" "$5"

	json_close_object
}



########################
##### Main Program #####

# read arguments
while [ "$1" != "" ]
do
	case "$1" in
    	-h|-help|--help)
			bUsage=1
	    ;;
    	-v|-version|--version)
			bDeviceVersion=1
			bRepoVersion=0
	    ;;
	    -f|-force|--force)
			bCheck=0
			bUpgrade=1
		;;
		-c|-check|--check)
			bCheckOnly=1
		;;
	    -l|-latest|--latest)
			bLatest=1
		;;
	    -u|-ubus)
			bJsonOutput=1
	    ;;
	    *)
			echo "ERROR: Invalid Argument"
			echo ""
			bUsage=1
	    ;;
	esac

	shift
done


## print the script usage
if [ $bUsage == 1 ]
then
	Usage
	exit
fi


## get the current version
if [ $bDeviceVersion == 1 ]; then
	# find the version
	GetDeviceVersion

	if [ $bJsonOutput == 0 ]; then
		echo "> Device Firmware Version: $deviceVersion"
	fi
fi


## get the latest repo version
if [ $bRepoVersion == 1 ]; then
	# find the remote version file to be used
	if [ $bLatest == 0 ]; then
		# use the stable version
		repoFile="$repoUrl/$repoStableFile"
	else
		# use the latest version
		repoFile="$repoUrl/$repoLatestFile"
	fi

	if [ $bJsonOutput == 0 ]; then
		echo "> Checking latest version online..."
	fi

	# fetch the repo version
	GetRepoVersion

	if [ $bJsonOutput == 0 ]; then
		echo "> Repo Firmware Version: $repoVersion"
	fi
else
	# optional exit here if just getting device version 
	if [ $bJsonOutput == 1 ]; then
		json_init
		JsonAddVersion "device" $deviceVersion $deviceVersionMajor $deviceVersionMinor $deviceVersionRev
		json_dump
	fi

	exit
fi


## compare the versions
if 	[ $bCheck == 1 ]
then
	if [ $bJsonOutput == 0 ]; then
		echo "> Comparing version numbers"
	fi

	if 	[ $repoVersionMajor -gt $deviceVersionMajor ]
	then
		bUpgrade=1
	elif 	[ $repoVersionMajor -eq $deviceVersionMajor ] &&
		 	[ $repoVersionMinor -gt $deviceVersionMinor ];
	then
		bUpgrade=1
	elif 	[ $repoVersionMajor -eq $deviceVersionMajor ] &&
		 	[ $repoVersionMinor -eq $deviceVersionMinor ] &&
		 	[ $repoVersionRev -gt $deviceVersionRev ];
	then
		bUpgrade=1
	fi
fi


## generate script info output (json and stdout)
if [ $bJsonOutput == 1 ]
then
	## json output
	json_init

	# upgrading firmware or not
	if [ $bUpgrade == 1 ]; then
		json_add_string "upgrade" "true"
	else
		json_add_string "upgrade" "false"
	fi

	# image info
	json_add_object "image"
	json_add_string "binary" "$binaryName"
	json_add_string "url" "$repoBinary"
	json_add_string "local" "$localBinary"
	json_close_object

	# version info
	JsonAddVersion "device" $deviceVersion $deviceVersionMajor $deviceVersionMinor $deviceVersionRev
	JsonAddVersion "repo" $repoVersion $repoVersionMajor $repoVersionMinor $repoVersionRev

	json_dump
else
	# stdout
	if [ $bUpgrade == 1 ]; then
		echo "> New firmware available, need to upgrade device firmware"
	else
		echo "> Device firmware is up to date!"
	fi
fi


## exit route if only checking if upgrade is required
if [ $bCheckOnly == 1 ]
then
	exit
fi


## perform the firmware upgrade
if [ $bUpgrade == 1 ]
then
	if [ $bJsonOutput == 0 ]; then
		echo "> Downloading new firmware ..."
	fi

	
	# delete any local firmware with the same name
	if [ -f $localBinary ]; then
		eval rm -rf $localBinary
	fi

	# setup wget verbosity
	local verbosity="-q"
	if [ $bJsonOutput == 0 ]; then
		verbosity=""
	fi

	# download the new firmware
	while [ ! -f $localBinary ]
	do
		wget $verbosity -O $localBinary "$repoBinary"
	done

	# start firmware upgrade
	sleep 5 	# wait 5 seconds before starting the firmware upgrade
	if [ $bJsonOutput == 0 ]; then
		echo "> Starting firmware upgrade...."
	fi

	sysupgrade $localBinary
fi





