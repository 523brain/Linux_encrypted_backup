#!/bin/bash
#This script could be executed in the STARTUP APPLICATIONS

##########################  SPECIFY PARAMETERS HERE  ###########################
ENCRYPTION_CONTAINERS=(1 /path/to/container1 \
					   2 /path/to/container2)

GRIVE_DIR=''
LOGFILE=./Logs/Log_sync.log
TIME_LAST_EXEC=604800	#one week in seconds

BACKUP_FILES=()
###############################################################################


function validate_fields() {
	text="Variable neither as parameter nor in script defined: "

	if [[ -z $GRIVE_DIR ]]
	then
		PROBLEMS+=("$text -g (grive directory)")
	elif !(test -d $GRIVE_DIR)
	then
		PROBLEMS+=('Specified grive path '$GRIVE_DIR' does not exist')
	fi

	if [[ -z $TIME_LAST_EXEC ]]
	then
		PROBLEMS+=("$text -t (seconds since backup)")
	fi

	if [[ -z $BACKUP_FILES ]] && ! $MB_FLAG
	then
		PROBLEMS+=('No backup files defined for backup')
	fi
}


function check_necessary_programs_installed() {
	programs=('veracrypt - https://veracrypt.codeplex.com/' 'grive - https://github.com/Grive/grive')
	not_installed=''

	for i in "${programs[@]}"
	do
		RET=`which $i`
		if [[ -z "$RET" ]]
		then
			not_installed+="\t$i\n"
		fi
	done

	if [[ ! -z $not_installed ]]; then echo "$not_installed"; fi

	return 1
}


function check_mounted_devices() {
	RESULT=$(veracrypt -t -l 2>&1 | grep "$1" | sed -E 's/(.*)[0-9]:{1} (.*)/\2/' | cut -d ' ' -f 3) # -l list all mounted things; -t text mode
	echo $RESULT
}


function get_time_stamp() {
	time=$(date "+%H:%M:%S")
	echo "[$time]"
}


function log() {
	var=$(echo -e "$1" | tr -d '\n\r')

	if [[ ! -z "$var" ]]
	then
		time=`get_time_stamp`
		output="$time $var"
		echo -e "$output" >> $LOGFILE

		if $VERBOSE && [[ $# -eq 1 ]]
		then
			echo -e "$output" >&2
		fi
	fi
}


function exit_script() {
	log "\n\n" 0
	kill -s TERM $TOP_PID
}


function check_internet_conn() {
	RET=2
	wget -q --tries=3 --timeout=20 --spider http://google.com

	if [[ $? -ne 0 ]]
	then
		out="No internet connection detected!"
		if ! $1
		then
			log "$out; Only packing files can be done, with parameter -i"
			RESULT=0
		else
			log "$out"
			log "-i parameter specified, files are only packed!"
			RET=1
		fi
	fi

	echo $RET
}


function check_time_for_backup() {
	LAST_EXEC=$(head -1 $LOGFILE)
	re='^[0-9]+$'

	RES=0
	if [[ -n "$LAST_EXEC" ]] && [[ $LAST_EXEC =~ $re ]]
	then
		CURRENT_TIME=$(date +"%s")
		DIFF=$(($CURRENT_TIME-$LAST_EXEC))

		if [[ $DIFF -gt $TIME_LAST_EXEC ]]; then RES=1; else RES=$LAST_EXEC; fi
	else
		RES=1;
	fi

	if [[ $RES != 1 ]]
	then
		sec=$(($TIME_LAST_EXEC%60))
		TIME_LAST_EXEC=$(($TIME_LAST_EXEC/60))
		min=$(($TIME_LAST_EXEC%60))
		TIME_LAST_EXEC=$(($TIME_LAST_EXEC/60))
		hours=$(($TIME_LAST_EXEC%24))
		TIME_LAST_EXEC=$(($TIME_LAST_EXEC/24))
		days=$TIME_LAST_EXEC

		LAST_EXEC=$(echo $RES | perl -pe 's/(\d+)/localtime($1)/e')
		log "Last execution '$LAST_EXEC'"
		log "To early for execution, time to wait specified '${days}d ${hours}h ${min}m ${sec}s'"

		echo 1
	fi
}


function create_logfile_if_not_exist() {
	DIRNAME=$(dirname $LOGFILE)
	PRE_DIR=$(dirname $DIRNAME)

	if !(test -d $PRE_DIR)
	then
		echo -e "Directory '$PRE_DIR' for logfile directory '$DIRNAME' does not exist!"
		exit 1
	else
		if !(test -d $DIRNAME)
		then

			mkdir $(dirname $LOGFILE)
			touch $LOGFILE
		else
			if !(test -e $LOGFILE)
			then
				touch $LOGFILE
			fi
		fi
	fi
}


function mount_container() {
	ENC_CONT=$1
	log "Execute: veracrypt $ENC_CONT"

	RESULT=$(veracrypt $ENC_CONT)

	if [[ -n "$RESULT" ]]
	then
		log "$RESULT"
		echo "1"
	else
		MOUNTPOINT=$(check_mounted_devices $ENC_CONT)

		if [[ -z "$MOUNTPOINT" ]]
		then
			log "The encryption file could not be mounted (probably users fault): $ENC_CONT"
			echo "1"
		else
			echo $MOUNTPOINT
		fi
	fi
}


# It is quite tricky to determine the exact free space in the container
# Currently this is not correctly implemented, might be added in the future
function check_container_space() {
	MOUNTPATH=$1
	CONT_NR=$2

	cmd_rsync="rsync -arR "
	# cmd_rsync_dry_run="$cmd_rsync--dry-run --stats "
	cmd_container_space="df -B1 $MOUNTPATH | tail -1 | awk -F' ' '{print \$4}'"

	synch_files=""

	TOTAL_FILES=${#BACKUP_FILES[*]}
	for (( i=0; i<=$(( $TOTAL_FILES -1 )); i++ ))
	do
		FILE_CONT_NR=${BACKUP_FILES[$i]}
		FILE=${BACKUP_FILES[$i+1]}

		if [[ $CONT_NR -eq $FILE_CONT_NR ]]
		then
			synch_files+="$FILE "
		fi

		i=$i+1
	done

	if [[ ! -z "$synch_files" ]]
	then
		cmd_rsync+="$synch_files $MOUNTPATH"
		echo $cmd_rsync

		# cmd_rsync_dry_run+="$synch_files $MOUNTPATH | grep 'Total transferred file size' | awk -F' ' '{gsub(/,/,\"\",\$5); print \$5}'"
		# Check for space in the container -- TODO
		# log "Execute: $cmd_rsync_dry_run"
		# log "Execute: $cmd_container_space"
		# total_space_needed=`eval $cmd_rsync_dry_run`
		# total_space_available=`eval $cmd_container_space`
		#
		# if [[ "$total_space_needed" -gt "$total_space_available" ]]
		# then
		# 	log "Not enough space for backup in container!\n\t\tNeed $total_space_needed bytes\n\t\tAvailable $total_space_available bytes"
		# 	echo ""
		# else
		#
		# fi
	else
		log "No files to synchronize!"
		echo ""
	fi
}


function synchronize() {
	cmd_rsync=$(check_container_space $1 $2)

	if [[ ! -z "$cmd_rsync" ]]
	then
		log "Execute: $cmd_rsync"
		output=$($cmd_rsync 2>&1)

		if [[ ! -z $output ]]
		then
			log "Error rsync: $output"
			echo ""
		fi
		echo "1"
	else
		echo ""
	fi
}


function usage() {
	echo "Usage: $0 [-h] [-v] [-i] [-p | -b] [-f files] [-t time] [-l logfile] [-g grive_dir]";
	echo -e "\t-h Displays help";
	echo -e "\t-f Specify backup files";
	echo -e "\t-t Seconds that need to be passed since last update; if 0 always backup";
	echo -e "\t-l Specify logfile (default '$LOGFILE')";
	echo -e "\t-i Run also when no internet connection available (Only synchronize files)"
	echo -e "\t-b Only upload backup files, WITHOUT synchronizing them first!"
	echo -e "\t-p Only backup files"
	echo -e "\t-g Specify the directory in which grive has been setup"
	echo -e "\t-v Display log output"

	exit 1;
}


function handle_text_arguments() {
	if [[ $1 != "-l" ]]
	then
		log "$2"
	else
		echo -e "$2"
	fi

	usage
}


function arguments_missing() {
	handle_text_arguments "$1" "Arguments for the flag '$1' are missing!"
}


function invalid_arguments() {
	handle_text_arguments "" "Invalid arguemnts are used!"
}


###########################################################################
#############################  START MAIN  ################################
###########################################################################
trap "exit 1" TERM
export TOP_PID=$$
###########################################################################


###################  PARSE COMMAND LINE PARAMETERS  #######################
VERBOSE=false
MF_FLAG=false
MAN_FILES=()
MD_FLAG=false
T_FLAG=false
TIME=-1
ML_FLAG=false
MAN_LOGFILE=''
MI_FLAG=false
MB_FLAG=false
MG_FLAG=false
MAN_GRIVE=''
MP_FLAG=false

current=''

for i in $*
do
	if [[ $i == "-"* ]]
	then
		current=$i
		case $i in
			"-h") usage;;
			"-v") VERBOSE=true;;
			"-f") MF_FLAG=true;;
			"-d") MD_FLAG=true;;
			"-t") T_FLAG=true;;
			"-l") ML_FLAG=true;;
			"-i") MI_FLAG=true;;
			"-g") MG_FLAG=true;;
			"-b") MB_FLAG=true;;
			"-p") MP_FLAG=true;;
		esac
	else
		case $current in
			"-f") MAN_FILES+=($i);;
			"-t") TIME=$i;;
			"-l") MAN_LOGFILE=$i;;
			"-g") MAN_GRIVE=$i;;
		esac
	fi
done
###########################################################################


############################  SETUP LOGFILE  ##############################
if $ML_FLAG && [[ $MAN_LOGFILE == '' ]]
then
	arguments_missing "-l"
fi

if [[ ! -z $MAN_LOGFILE ]]
then
	LOGFILE=$MAN_LOGFILE
fi

if [[ -z $LOGFILE ]]
then
	echo -e "No logfile was specified; Check parameter -l or define it in the script"
	exit
fi

create_logfile_if_not_exist

log "==============  BACKUP --- $(date)  ==============="
###########################################################################


###############  CHECK IF NECESSARY PROGRAMS ARE INSTALLED  ###############
RET=`check_necessary_programs_installed`

if [[ ! -z $RET ]]
then
	log "The following necessary programs are not installed:\n$RET"
	exit_script
fi
###########################################################################


############################  CHECK PARAMETERS  #############################
if $MF_FLAG && [[ ${#MAN_FILES[@]} -eq 0 ]]; then arguments_missing "-f"; fi
if $T_FLAG && [[ $TIME -eq -1 ]]; then arguments_missing "-t"; fi
if $MG_FLAG && [[  $MAN_GRIVE == '' ]]; then arguments_missing "-g"; fi
if $MB_FLAG && $MP_FLAG; then invalid_arguments; fi
###########################################################################


#######################  SET DEFINED PARAMETERS  ##########################
if [[ ! -z $MAN_FILES ]]; then BACKUP_FILES=$MAN_FILES; fi
if [[ $TIME -ne -1 ]]; then TIME_LAST_EXEC=$TIME; fi
###########################################################################

###########################  VALIDATE FIELDS  #############################
PROBLEMS=()
validate_fields

if [[ ! -z $PROBLEMS ]]
then
	for PROBLEM in "${PROBLEMS[@]}"
	do
		log "$PROBLEM"
	done
	exit_script
fi
###########################################################################


############  CHECK IF ENOUGH TIME PASSED SINCE LAST EXECUTION  ###########
if [[ $TIME_LAST_EXEC -ne 0 ]]
then
	if [[ "$(check_time_for_backup)" == "1" ]]
	then
		exit_script
	fi
fi
###########################################################################


###############  CHECK IF INTERNET CONNECTION AVAILABLE  ##################
INET=$(check_internet_conn $MI_FLAG)
if [[ "$INET" == "0" ]]
then
	exit_script
fi
###########################################################################


# MB_FLAG -> only backup files to grive, without synchronizing anything
if ! $MB_FLAG
then
	total=${#ENCRYPTION_CONTAINERS[*]}

	for (( i=0; i<=$(( $total -1 )); i++ ))
	do
		CONTAINER_NR=${ENCRYPTION_CONTAINERS[$i]}
		ENCRYPTION_CONTAINER=${ENCRYPTION_CONTAINERS[$i+1]}

		#######################  CHECK FOR MOUNTED CONTAINERS  #########################
		MOUNTPOINT=$(check_mounted_devices $ENCRYPTION_CONTAINER)

		# if the container is not mounted yet do so
		if [[ -z "$MOUNTPOINT" ]]
		then
			MOUNTPOINT=$(mount_container $ENCRYPTION_CONTAINER)

			if [[ "$MOUNTPOINT" == "1" ]]
			then
				exit_script
			fi
		fi

		log "Mount point of $ENCRYPTION_CONTAINER is $MOUNTPOINT"
		###########################################################################

		######################  BACKUP FILES INTO CONTAINER  ######################
		return=$(synchronize $MOUNTPOINT $CONTAINER_NR)

		if [[ -z "$return" ]]
		then
			exit_script
		fi
		###########################################################################

		#########################  DISMOUNT CONTAINER  ############################
		RESULT=$(veracrypt --dismount $ENCRYPTION_CONTAINER 2>&1)

		if [ -n "$RESULT" ];
		then
			log "$RESULT"
			exit_script
		else
			log "Unmounted file $MOUNTPOINT ($ENCRYPTION_CONTAINER) correctly"
		fi
		###########################################################################

		i=$i+1
	done
fi


#########################  BACKUP FILE TO GOOGLE  #############################
if [[ $INET == "2" && "$MP_FLAG" == false ]]
then
	DIR_MAPPING=()

	# For all containers it has to be checked if they are in the same directory as the Grive Sync directory
	# If not, move them there and store the original path to move them back after the synchronization
	for (( i=0; i<=$(( $total -1 )); i++ ))
	do
		CONTAINER=${ENCRYPTION_CONTAINERS[$i+1]}
		DIR=$(dirname $CONTAINER)

		if [[ "$DIR" != "$GRIVE_DIR" ]]
		then
			BASE=$(basename $CONTAINER)
			DIR_MAPPING+=($BASE $DIR)

			mv $CONTAINER $GRIVE_DIR
		fi

		i=$i+1
	done

	log "Start backup..."
	log "Execute: grive -u -p $GRIVE_DIR"
	grive -u -p $GRIVE_DIR 2> >(gawk '{print strftime("[%T]", systime()), $0}' >&1) | tee -a $LOGFILE

	#move the containers back to their original place
	total=${#DIR_MAPPING[*]}
	for (( i=0; i<=$(( $total -1 )); i++ ))
	do
		BASE=${DIR_MAPPING[$i]}
		DESTINATION=${DIR_MAPPING[i+1]}

		mv $GRIVE_DIR/$BASE $DESTINATION

		i=$i+1
	done
fi
###########################################################################


################  TIMESTAMP OF EXECUTION ON TOP OF LOGFILE  ###############
TIMESTAMP=$(date +"%s")
perl -i -pe "s/.*/$TIMESTAMP/ if $.==1" $LOGFILE

echo -e "\n\n" >> $LOGFILE
###########################################################################
