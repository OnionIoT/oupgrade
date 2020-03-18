#!/bin/sh

# include the json sh library
. /usr/share/libubox/jshn.sh

# setup variables
bCmdUsage=0
bCmdFwUpgrade=1
bCmdDeviceVersion=0
bCmdCheck=0
bCmdAcknowledge=0

bForceUpgrade=0

bDeviceVersion=1
bRepoVersion=1
bCheck=1
bLatest=0
bUpgrade=0
bBuildMismatch=0
bJsonOutput=0
bCheckOnly=0
bDebug=0

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
notePath="/etc/oupgrade"

# change repo url based on device type
urlBase=""
device=""
repoUrl=""

repoStableFile="stable"
repoLatestFile="latest"
timeout=500

SCRIPT=$0

LOGGING=1
LOGFILE="/tmp/oupgrade.log"
PACKAGE=onion
FIRMWARE_CONFIG=${PACKAGE}.@${PACKAGE}[0]



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

_log()
{
		if [ ${LOGGING} -eq 1 ]; then
				local ts=$(date)
				echo "$ts $@" >> ${LOGFILE}
		fi
}

_exit()
{
    local rc=$1
    exit ${rc}
}

_get_uci_value_raw()
{
		local value
		value=$(uci -q get $1 2> /dev/null)
		local rc=$?
		echo ${value}
		return ${rc}
}

_get_uci_value()
{
		local value
		value=$(_get_uci_value_raw $1)
		local rc=$?
		if [ ${rc} -ne 0 ]; then
				_log "Could not determine UCI value $1"
				return 1
		fi
		echo ${value}
}

# print to stdout if not doing json output
#	arg1	- the text to print
Print () {
	if [ $bJsonOutput == 0 ]; then
		echo "$1" > /dev/console
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
#   populates following global variables
#     deviceVersion
#     deviceVersionMajor
#     deviceVersionMinor
#     deviceVersionRev
#     deviceBuildNum
GetDeviceVersion () {
	local ver=$(_get_uci_value ${FIRMWARE_CONFIG}.version)
	if [ "$ver" != "" ]; then
		# read the device version
		deviceVersion=$ver

		# read the sub-version info
		deviceVersionMajor=$(GetVersionMajor "$deviceVersion")
		deviceVersionMinor=$(GetVersionMinor "$deviceVersion")
		deviceVersionRev=$(GetVersionRevision "$deviceVersion")

		# read the build number
		local build=$(_get_uci_value ${FIRMWARE_CONFIG}.build)
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
	local url="$1"
	local outFile=$(mktemp)

	# fetch the file
	local resp=$(wget "$url" -O "$outFile" 2>&1)
	local ret=$?

	if [ $? -eq 0 ]; then
		# parse the json file
		local RESP="$(cat $outFile)"
		# echo "response is $RESP"

		json_load "$RESP"

		# check the json file contents
		json_get_var repoVersion version
		# echo "repoVersion $repoVersion"

		repoVersionMajor=$(GetVersionMajor "$repoVersion")
		repoVersionMinor=$(GetVersionMinor "$repoVersion")
		repoVersionRev=$(GetVersionRevision "$repoVersion")

		json_get_var repoBuildNum build
		# echo "repoBuildNum $repoBuildNum"

		# parse the binary url
		json_get_var repoBinary url
		binaryName=${repoBinary##*/}

		localBinary="$tmpPath/$binaryName"

		fileSize=$(GetFileSize "$repoBinary")

		# echo "repoVersionMajor $repoVersionMajor"
		# echo "repoVersionMinor $repoVersionMinor"
		# echo "repoVersionRev $repoVersionRev"
	fi
	# echo "$ret"
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

# function to add version info to json
# arguments
#		object name
#		version number
# 	build number
JsonAddVersionInfo () {
	# local versionNumber="$2"
	json_add_object "$1"
	
	local major=$(GetVersionMajor "$2")
	local minor=$(GetVersionMinor "$2")
	local rev=$(GetVersionRevision "$2")

	json_add_string "version" "$2"
	json_add_int 	"major" "$major"
	json_add_int 	"minor" "$minor"
	json_add_int 	"revision" "$rev"
	json_add_int 	"build" "$3"

	json_close_object
}

generateScriptInfoOutput () {
	
	if [ $bJsonOutput == 1 ]
	then
		
		## json output
		json_init

		# upgrading firmware or not
		json_add_boolean "upgrade" $1
		# version mismatch
		json_add_boolean "build_mismatch" $2
		#image info
		json_add_object "image"
		json_add_string "binary" "$3"
		json_add_string "url" "$4"
		json_add_string "local" "$5"
		json_add_string "size" "$6"
		json_close_object

		# version info
		JsonAddVersionInfo "device" $7 $8
		JsonAddVersionInfo "repo" $9 $10

		json_dump > /dev/console
	else
		# stdout
		if [ $1 == 1 ]; then
			Print "> New firmware version available, need to upgrade device firmware"
		elif [ $2 == 1 ]; then
			Print "> New build of current firmware available, upgrade is optional, rerun with '-force' option to upgrade"
		else
			Print "> Device firmware is up to date!"
		fi
	fi
}

# function to compare versions and determine if upgrade is necessary
# arguments
#		new version number 
#		old version number 
VersionNumberCompare () {
	local newVersion="$1"
	local oldVersion="$2"

	local newVersionMajor=$(GetVersionMajor "$newVersion")
	local newVersionMinor=$(GetVersionMinor "$newVersion")
	local newVersionRev=$(GetVersionRevision "$newVersion")
	
	local oldVersionMajor=$(GetVersionMajor "$oldVersion")
	local oldVersionMinor=$(GetVersionMinor "$oldVersion")
	local oldVersionRev=$(GetVersionRevision "$oldVersion")
	
	local bUpgradeReq=0
	
	if 	[ $newVersionMajor -gt $oldVersionMajor ]
	then
		bUpgradeReq=1
	elif 	[ $newVersionMajor -eq $oldVersionMajor ] &&
			[ $newVersionMinor -gt $oldVersionMinor ];
	then
		bUpgradeReq=1
	elif 	[ $newVersionMajor -eq $oldVersionMajor ] &&
			[ $newVersionMinor -eq $oldVersionMinor ] &&
			[ $newVersionRev -gt $oldVersionRev ];
	then
		bUpgradeReq=1
	fi
	
	echo $bUpgradeReq
}

# function to compare build numbers and determine if upgrade is necessary
# arguments
#		new build number
# 	old build number 
BuildNumberCompare () {
	local newBuildNumber=$1
	local oldBuildNumber=$2
	
	local bBuildsDiff=0
	
	if [ $newBuildNumber -gt $oldBuildNumber ]; then
		bBuildsDiff=1
	fi

	echo $bBuildsDiff
}

# read firmware API from UCI
ReadFirmwareApiUrl () {
	local url=$(_get_uci_value ${PACKAGE}.oupgrade.api_url)
	# keep hardcoded default as a fallback
	if [ "$url" == "" ]; then
		url="https://api.onioniot.com/firmware"
	fi
	echo "$url"
}

# read if update acknowledge is enabled
ReadUpdateAcknowledgeEnabled () {
	local ret=0
	local bEnabled=$(_get_uci_value ${PACKAGE}.oupgrade.ack_upgrade)
	if [ "$bEnabled" == 1 ]; then
		ret=1
	fi
	echo $ret
}

## read device's MAC addr for ra0 intf
getMacAddr () {
	# grab line 2 of iwpriv output
	line1=$(iwpriv ra0 e2p | sed -n '2p')
	# isolate bytes at addresses 0x0004 and 0x0006, and perform byte swap
	bytes5432=$(echo $line1 | awk '{print $3":"$4}' | \
	awk -F ":" \
	'{print substr($2,3) substr($2,1,2) substr($4,3) substr($4,1,2)}')
	# grab line 3 of iwpriv output
	line2=$(iwpriv ra0 e2p | sed -n '3p')
	# isolate bytes at address 0x0008 and perform byte swap
	bytes10=$(echo $line2 | awk '{print $1}' | \
	awk -F ":" '{print substr($2,3) substr($2,1,2)}')
	macId=$(echo ${bytes5432}${bytes10})
	echo $macId
}

# send http request to acknowledge firmware update
# arguments:
# 	firmware version to report
# 	firmware build to report
#		upgrade status (starting, complete)
HttpUpdateAcknowledge () {
	# create the data payload to be sent in the HTTP Post request
	#		mac_addr
	#		device (omega2, omega2p)
	# 	firmware_version
	# 	firmware_build
	#		upgrade_status (starting, complete)
	local data="mac_addr=$(getMacAddr)&device=$(ubus call system board | jsonfilter -e '@.board_name')&firmware_version=${1}&firmware_build=${2}&upgrade_status=${3}"
	local verbosity="-q"
	
	# before performing HTTP request, check if update acknowledge is enable
	local bEnabled=$(ReadUpdateAcknowledgeEnabled)
	if [ $bEnabled == 1 ]; then
		count=0
		maxCount=10
		while [ 1 ]; do
			wget $verbosity --post-data "$data" -O /tmp/null $urlBase
			if [ $? -eq 0 ]; then
				break
			fi
			if [ $count -gt $maxCount ]; then
				_log "Not able to send upgrade acknowledge after $maxCount retries"
				break
			fi
			
			# wait and try again
			sleep 1
			count=$(($count+1))
		done
	fi
}

printDeviceVersion () {
	local ret
	Print "> Device Firmware Version: $deviceVersion b$deviceBuildNum"
	if [ $bJsonOutput == 1 ]; then
		json_init
		JsonAddVersionInfo "device" $deviceVersion $deviceBuildNum
		ret=$(json_dump)
	fi
	echo "$ret"
}

# arguments
#	 bLatestFirmware : 1 for latest, 0 for stable
buildFirmwareUrl () {
	local bLatestFirmware=$1
	local urlBase=$(ReadFirmwareApiUrl)
	local device=$(ubus call system board | jsonfilter -e '@.board_name')
	local firmwareType="stable"
	local url
	
	if [ "$bLatestFirmware" == "1" ]; then
		# use the stable version
		firmwareType="latest"
	fi
	
	url="${urlBase}/${device}/${firmwareType}"
	_log "Using firmware url $url"
	echo "$url"
}

# arguments
#	 bLatestFirmware : 1 for latest, 0 for stable
getOnlineFirmwareInfo () {
	local bLatestFirmware=$1
	local url=$(buildFirmwareUrl $bLatestFirmware)
	local resp
	local outFile=$(mktemp)
	
	Print "> Checking latest version online..."
	Print "url: $url"
	
	local count=0
	local maxCount=10
	while [ 1 ]; do
		resp=$(wget "$url" -O "$outFile" 2>&1)
		
		if [ $? -eq 0 ]; then
			break
		fi 
		if [ $count -gt $maxCount ]; then
			_log "Not able to communicate with firmware API after $maxCount retries"
			break
		fi
		
		sleep 1
		count=$(($count+1))
	done
	
	echo $(cat $outFile)
	return $?
}

downloadInstallFirmware () {
	local localBinaryPath="$1"
	local binaryUrl="$2"
	local repoVersion="$3"
	local repoBuildNum="$4"
	
	Print "> Downloading new firmware ..."

	# delete any local firmware with the same name
	if [ -f $localBinaryPath ]; then
		eval rm -rf $localBinaryPath
	fi
	# setup wget verbosity
	verbosity="-q"
	if [ $bJsonOutput == 0 ]; then
		verbosity=""
	fi

	# download the new firmware
	count=0
	maxCount=10
	while [ 1 ]; do
		wget $verbosity -O $localBinaryPath "$binaryUrl"
		if [ $? -eq 0 ]; then
			break
		fi
		if [ $count -gt $maxCount ]; then
			_log "Not able to download firmware after $maxCount retries"
			Print "> ERROR: Downloading firmware has failed! Try again!"
			_exit 1
		fi
		
		# wait and try again
		sleep 1
		count=$(($count+1))
	done
	
	# start firmware upgrade
	Print "> Starting firmware upgrade...."
	HttpUpdateAcknowledge $repoVersion $repoBuildNum "starting"
	sleep 5 	# wait 5 seconds before starting the firmware upgrade
	
	if [ $bDebug == 0	 ]; then
		sysupgrade $localBinaryPath
	fi
}

checkUpgradeRequired () {
	local bLatest=$1
	_log "checkUpgradeRequired bLatest = $bLatest"
	printDeviceVersion
	fwInfo=$(getOnlineFirmwareInfo $bLatest)
	
	# parse json response
	json_load "$fwInfo"
	local repoVersion
	json_get_var repoVersion version
	local repoVersionMajor=$(GetVersionMajor "$repoVersion")
	local repoVersionMinor=$(GetVersionMinor "$repoVersion")
	local repoVersionRev=$(GetVersionRevision "$repoVersion")
	local repoBuildNum
	json_get_var repoBuildNum build
	local binaryUrl
	json_get_var binaryUrl url
	local binaryName=${binaryUrl##*/}
	local localBinaryPath="$tmpPath/$binaryName"
	local fileSize=$(GetFileSize "$binaryUrl")
	
	if [ "$repoVersion" == "" ]; then
		Print "> ERROR: Could not connect to Onion Firmware Server!"
		_exit 1
	fi
	Print "> Repo Firmware Version: $repoVersion b$repoBuildNum"
	
	# compare version numbers
	Print "> Comparing version numbers"
	local bUpgrade=$(VersionNumberCompare $repoVersion $deviceVersion)
	local bBuildMismatch
	## compare the build numbers (only if versions are the same)
	if 	[ $bUpgrade == 0 ]
	then
		bBuildMismatch=$(BuildNumberCompare $repoBuildNum $deviceBuildNum)
	fi
	
	## generate script info output (json and stdout)
	generateScriptInfoOutput $bUpgrade $bBuildMismatch $binaryName $binaryUrl $localBinaryPath $fileSize $deviceVersion $deviceBuildNum $repoVersion $repoBuildNum

	echo "$fwInfo"
	return $bUpgrade
}

firmwareUpgrade1 () {
	local bLatest=$1
	local bForceUpgrade=$2
	local fwInfo
	local bUpgrade
	
	fwInfo=$(checkUpgradeRequired $1)
	bUpgrade=$?
	
	_log "upgrade required = $bUpgrade"
	
	## parse the json fw info
	json_load "$fwInfo"
	local binaryUrl
	json_get_var binaryUrl url
	local binaryName=${binaryUrl##*/}
	local localBinaryPath="$tmpPath/$binaryName"
	local repoVersion
	json_get_var repoVersion version
	local repoBuildNum
	json_get_var repoBuildNum build
	
	## perform the upgrade if needed
	if [ $bUpgrade -eq 1 ] || [ $bForceUpgrade -eq 1 ]; then		
		downloadInstallFirmware $localBinaryPath $binaryUrl $repoVersion $repoBuildNum
	fi 
}

# perform a firmware upgrade if required
firmwareUpgrade () {
	## get the current version
	if [ $bDeviceVersion == 1 ]; then
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
			Print "> ERROR: Could not connect to Onion Firmware Server!"
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
		bUpgrade=$(VersionNumberCompare $repoVersion $deviceVersion)
	fi


	## compare the build numbers (only if versions are the same)
	if 	[ $bUpgrade == 0 ]
	then
		bBuildMismatch=$(BuildNumberCompare $repoBuildNum $deviceBuildNum)
	fi


	## generate script info output (json and stdout)
	if [ $bJsonOutput == 1 ]
	then
		## json output
		json_init

		# upgrading firmware or not
		json_add_boolean "upgrade" $bUpgrade

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
		verbosity="-q"
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
			HttpUpdateAcknowledge $repoVersion $repoBuildNum "starting"

			if [ $bDebug == 0	 ]; then
				sysupgrade $localBinary
			fi
		else
			Print "> ERROR: Downloading firmware has failed! Try again!"
		fi
	fi
}

upgradeCompleteAcknowledge () {
	local bAckRequired=0
	
	# check if firmware has just been updated by checking the oupgrade note file:
	# 1. if the note file doesn't exist - upgrade has been completed -> create note file and acknowledge update
	# 2. if note file exists and version data doesn't match that of the device -> update note file and acknowledge update
	# 3. everything else -> do nothing
	
	# check if firmware note file exists
	if [ -f $notePath ]; then
		_log "note file $notePath exists"
		local recordedVersion=$(cat $notePath | awk '{print $1;}')
		local recordedBuildNumber=$(cat $notePath | awk '{print $2;}')
		
		local bDiffVersion=$(VersionNumberCompare $deviceVersion $recordedVersion)
		local bDiffBuild=$(BuildNumberCompare $deviceBuildNum $recordedBuildNumber)
		
		if [ $bDiffVersion == 1 ] || [ $bDiffBuild == 1 ]; then
			_log "note file holds different version"
			bAckRequired=1
		fi
	else
		_log "note file $notePath does not exist"
		bAckRequired=1
	fi
	
	# peform the acknowledge if required
	if [ $bAckRequired == 1 ]; then
		_log "upgrade acknowledge required" 
		#update the note file
		echo "$deviceVersion $deviceBuildNum" > $notePath
		# perform the update acknowledge
		HttpUpdateAcknowledge $deviceVersion $deviceBuildNum "complete"
	fi
}

_cron_restart()
{
	/etc/init.d/cron restart > /dev/null
}

_add_cron_script()
{
	(crontab -l ; echo "$1") | sort | uniq | crontab -
	_cron_restart
}

_rm_cron_script()
{
	crontab -l | grep -v "$1" |  sort | uniq | crontab -
	_cron_restart
}

_create_cron_entries() {
	local updateFrequency
	updateFrequency=$(_get_uci_value ${PACKAGE}.oupgrade.update_frequency) || _exit 1
	
	local cronInterval
	if [ "$updateFrequency" == "daily" ]; then
		cronInterval="0 0 * * *"
	elif [ "$updateFrequency" == "weekly" ]; then
		cronInterval="0 0 * * 0"
	elif [ "$updateFrequency" == "monthly" ]; then
		cronInterval="0 0 1 * *"
	else
	  _log "Invalid automatic update frequency"
		_exit 1
	fi
	
	_add_cron_script "${cronInterval} ${SCRIPT} -l -f  # ${updateFrequency} automatic firmware upgrade"
}

check_cron_status()
{
	local autoUpdateEnabled
	autoUpdateEnabled=$(_get_uci_value ${PACKAGE}.oupgrade.auto_update) || _exit 1
	_rm_cron_script "${SCRIPT}"
	if [ ${autoUpdateEnabled} -eq 1 ]; then
		_create_cron_entries 
	fi
}


########################
##### Main Program #####

### populate important global variables
GetDeviceVersion
urlBase=$(ReadFirmwareApiUrl)
device=$(ubus call system board | jsonfilter -e '@.board_name')
repoUrl="$urlBase/$device"

# read arguments
while [ "$1" != "" ]
do
	case "$1" in
		# options
		-h|-help|--help)
			bCmdUsage=1
		;;
		-f|-force|--force)
			bCheck=0
			bUpgrade=1
			bForceUpgrade=1
		;;	
		-l|-latest|--latest)
			bLatest=1
		;;
		-u|-ubus|-j|-json|--json)
			bJsonOutput=1
		;;
		-d|-debug|--debug)
			bDebug=1
		;;
		## specific operations
		-v|-version|--version|version)
			bCmdDeviceVersion=1
		;;
		-c|-check|--check|check)
			bCmdCheck=1
		;;
		-a|-acknowledge|--acknowledge|acknowledge)
			upgradeCompleteAcknowledge
			_exit 0
		;;
		autoupdate|-autoupdate|--autoupdate)
			check_cron_status
			_exit 0
		;;
		*)
			echo "ERROR: Invalid Argument"
			echo ""
			bCmdUsage=1
		;;
	esac

	shift
done


## print the script usage
if [ $bCmdUsage == 1 ]
then
	Usage
	_exit 0
fi


## perform commands
if [ $bCmdDeviceVersion == 1 ]; then
	ver=$(printDeviceVersion)
	echo $ver
elif [ $bCmdCheck == 1 ]; then
	ret=$(checkUpgradeRequired $bLatest)
elif [ $bCmdFwUpgrade == 1 ]; then 
	#firmwareUpgrade
	firmwareUpgrade1 $bLatest $bForceUpgrade
fi 
