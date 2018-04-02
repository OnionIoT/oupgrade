#!/bin/sh

# include the Onion sh lib
. /usr/lib/onion/lib.sh

# setup variables
bUsage=0
bDeviceVersion=1
bRepoVersion=1
bCheck=1
bLatest=0
bUpgrade=0
bBuildMismatch=0
bJsonOutput=0
bCheckOnly=0

deviceVersion=""
deviceVersionMajor=""
deviceVersionMinor=""
deviceVersionRev=""
deviceBuildNum=""

repoVersion=""
repoVersionMajor=""
repoVersionMinor=""
repoVersionRev=""
repoBuildNum=""

repoBinary=""
binaryName=""

fileSize=""

tmpPath="/tmp"

# change repo url based on device type
urlBase="https://api.onion.io/firmware"
device=$(ubus call system board | jsonfilter -e '@.board_name')

repoUrl="$urlBase/$device"

repoStableFile="stable"
repoLatestFile="latest"
timeout=500




# function to print script usage
Usage () {
    echo "Functionality:"
    echo "  Check if new Onion firmware is available and perform upgrade"
    echo ""
    echo "Usage: $0"
    echo ""
    echo "Arguments:"
    echo " -h, --help        Print this usage prompt"
    echo " -v, --version     Just print the current firmware version"
    echo " -l, --latest      Use latest repo version (instead of stable version)"
    echo " -f, --force       Force the upgrade, regardless of versions"
    echo " -c, --check       Only compare versions, do not actually update"
    echo " -u, --ubus        Script outputs only json"

    echo ""
}

# print to stdout if not doing json output
#	arg1	- the text to print
Print () {
	if [ $bJsonOutput == 0 ]; then
		echo "$1"
	fi
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

# function to read remote file size
GetFileSize () {
	ret=$(wget --spider $1 2>&1 | grep Length | awk '{print $2}')
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

		# read the build number
		local build=$(uci -q get onion.@onion[0].build)
		if [ "$build" != "" ]; then
			deviceBuildNum=$build
		else
			deviceBuildNum=0
		fi
	else
		deviceVersion="unknown"
	fi
}

# function to read latest repo version
#	arg1	- url of file to download
GetRepoVersion () {
	local outFile=$(mktemp)

	# fetch the file
	if [ "$(DownloadUrl "$1" "$outFile")" == "1" ]; then
		return
	fi

	if [ $? -eq 0 ]; then
		# parse the json file
		local RESP="$(cat $outFile)"
		json_load "$RESP"

		# check the json file contents
		json_get_var repoVersion version

		repoVersionMajor=$(GetVersionMajor "$repoVersion")
		repoVersionMinor=$(GetVersionMinor "$repoVersion")
		repoVersionRev=$(GetVersionRevision "$repoVersion")

		json_get_var repoBuildNum build

		# parse the binary url
		json_get_var repoBinary url
		binaryName=${repoBinary##*/}

		localBinary="$tmpPath/$binaryName"

		fileSize=$(GetFileSize "$repoBinary")
	fi
}

# function to add version info to json
JsonAddVersion () {
	json_add_object "$1"

	json_add_string "version" "$2"
	json_add_int 	"major" "$3"
	json_add_int 	"minor" "$4"
	json_add_int 	"revision" "$5"
	json_add_int 	"build" "$6"

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

	Print "> Device Firmware Version: $deviceVersion b$deviceBuildNum"
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

	Print "> Checking latest version online..."
	Print "url: $repoFile"

	# fetch the repo version
	GetRepoVersion $repoFile
	if [ "$repoVersion" == "" ]; then
		Print "> ERROR: Could not connect to Onion Firmware Server! Check your internet connection and try again!"
		exit
	fi

	Print "> Repo Firmware Version: $repoVersion b$repoBuildNum"
else
	# optional exit here if just getting device version
	if [ $bJsonOutput == 1 ]; then
		json_init
		JsonAddVersion "device" $deviceVersion $deviceVersionMajor $deviceVersionMinor $deviceVersionRev $deviceBuildNum
		json_dump
	fi

	exit
fi


## compare the versions
if 	[ $bCheck == 1 ]
then
	Print "> Comparing version numbers"

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


## compare the build numbers (only if versions are the same)
if 	[ $bUpgrade == 0 ]
then
	if [ $repoBuildNum -gt $deviceBuildNum ]; then
		bBuildMismatch=1
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

	# version mismatch
	json_add_boolean "build_mismatch" $bBuildMismatch

	# image info
	json_add_object "image"
	json_add_string "binary" "$binaryName"
	json_add_string "url" "$repoBinary"
	json_add_string "local" "$localBinary"
	json_add_string "size" "$fileSize"
	json_close_object

	# version info
	JsonAddVersion "device" $deviceVersion $deviceVersionMajor $deviceVersionMinor $deviceVersionRev $deviceBuildNum
	JsonAddVersion "repo" $repoVersion $repoVersionMajor $repoVersionMinor $repoVersionRev $repoBuildNum

	json_dump
else
	# stdout
	if [ $bUpgrade == 1 ]; then
		echo "> New firmware version available, need to upgrade device firmware"
	elif [ $bBuildMismatch == 1 ]; then
		echo "> New build of current firmware available, upgrade is optional, rerun with '-force' option to upgrade"
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
	Print "> Downloading new firmware ..."

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
	if [ $? -eq 0 ]; then
		sleep 5 	# wait 5 seconds before starting the firmware upgrade
		Print "> Starting firmware upgrade...."

		sysupgrade $localBinary
	else
		Print "> ERROR: Downloading firmware has failed! Try again!"
	fi
fi
