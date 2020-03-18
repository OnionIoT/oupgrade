#!/bin/sh

# check for argument
if [ "$1" == "" ]
then
    echo "ERROR: expecting Omega address as argument!"
    echo "$0 <address>"
    exit
fi

ADDR="$1"

# upload the script
localPath="oupgrade.sh"
remotePath="/usr/bin/oupgrade"

cmd="rsync -va --progress $localPath root@$ADDR:$remotePath"
echo "$cmd"
$cmd

# upload the init.d file
localPath="init.d/oupgrade"
remotePath="/etc/init.d/oupgrade"

cmd="rsync -va --progress $localPath root@$ADDR:$remotePath"
echo "$cmd"
$cmd
