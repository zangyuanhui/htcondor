#!/usr/bin/env bash

##**************************************************************
##
## Copyright (C) 1990-2018, Condor Team, Computer Sciences Department,
## University of Wisconsin-Madison, WI.
##
## Licensed under the Apache License, Version 2.0 (the "License"); you
## may not use this file except in compliance with the License.  You may
## obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##
##**************************************************************

# This script launches the orted command generated by mpirun, after
# some HTCondor-specific setup and modifications.

# Get a unique filename to store the command
ORTED_CMD=orted_cmd
while [ -f $_CONDOR_SCRATCH_DIR/$ORTED_CMD ]; do
    ORTED_CMD=x$ORTED_CMD
done
ORTED_CMD=$_CONDOR_SCRATCH_DIR/$ORTED_CMD

# Fetch the orted command from the schedd
CONDOR_CHIRP=$(condor_config_val libexec)/condor_chirp
_stat_old=""
while [ ! -f $ORTED_CMD ]; do
    sleep 1 # Check every second

    # Only fetch the orted command when it has stopped being modified
    _stat=$($CONDOR_CHIRP stat $_CONDOR_REMOTE_SPOOL_DIR/orted_cmd.$_CONDOR_PROCNO 2>&1)
    if echo $_stat | grep '^Error' > /dev/null; then # file not found
	continue 
    elif [ $(echo $_stat | grep -oP '(?<!k)(size: )\K\d+') -eq 0 ]; then # size 0
	continue
    elif [ "$_stat" = "$_stat_old" ]; then # unchanged
	$CONDOR_CHIRP fetch $_CONDOR_REMOTE_SPOOL_DIR/orted_cmd.$_CONDOR_PROCNO $ORTED_CMD
    fi
    _stat_old="$_stat"
    
done

# Cleanup the orted command from the schedd
$CONDOR_CHIRP remove $_CONDOR_REMOTE_SPOOL_DIR/orted_cmd.$_CONDOR_PROCNO

# Modify the command to remove the daemonize mode
sed -i '$s|--daemonize||' $ORTED_CMD

# Modify the command to put the tmpdir under the scratch directory
mkdir -p $_CONDOR_SCRATCH_DIR/tmp
sed -i 's|$| --tmpdir '"$_CONDOR_SCRATCH_DIR"'/tmp|' $ORTED_CMD

# Set $HOME to the current directory
export HOME=$(pwd)

# Trap SIGTERM and run cleanup
_orted_pid=0
force_cleanup() {
    $CONDOR_CHIRP ulog "Node $_CONDOR_PROCNO caught SIGTERM, cleaning up orted"
    rm $ORTED_CMD
    if [ "$_orted_pid" -ne "0" ]; then

	# Send SIGTERM to mpirun and the orted launcher
	echo "$0 - Sending SIGTERM to orted..."
	kill -s SIGTERM $_orted_pid

	# Give mpirun 30 seconds to terminate nicely
	echo "Waiting for orted to exit..."
	for i in {1..30}; do
	    kill -0 $_orted_pid 2> /dev/null # returns 0 if running
	    _orted_killed=$?
	    if [ $_orted_killed -ne 0 ]; then
		break
	    fi
	    sleep 1
	done

	# If orted is still running, send SIGKILL
	if [ $_orted_killed -eq 0 ]; then
	    $CONDOR_CHIRP ulog "orted hung on Node ${_CONDOR_PROCNO}, sending SIGKILL!"
	    kill -s SIGKILL $_orted_pid
	fi
	
    fi
    exit 1
}
trap force_cleanup SIGTERM

# Run the orted command
$CONDOR_CHIRP ulog "Launching orted on Node $_CONDOR_PROCNO of $_CONDOR_NPROCS"
. $ORTED_CMD
_orted_pid=$!
wait $_orted_pid
_orted_exit=$?
$CONDOR_CHIRP ulog "orted exited on Node $_CONDOR_PROCNO of $_CONDOR_NPROCS"

# Cleanup orted command
rm $ORTED_CMD
exit $_orted_exit
