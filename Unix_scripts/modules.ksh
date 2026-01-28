#!/bin/ksh


module_cfg=
log_dir=
min_log_level=
HOLD_STOP_DIR=

if [ -f $module_cfg ]; then
	. $module_cfg
else
	cr_dt=$(date '+%Y%m%d')
	cr_tm=$(date '+%Y%m%d %H:%M:%S')
	prid=$$
	Logfile="e/unix_scripts/logs/Common_Modules.$cr_dt.log"
	echo "$cr_tm [$prid] - [ERROR] - common_module config file not fount \"$module_cfg\""
	exit
fi


process_name=$(basename "$0" .ksh)    ## will give the calling script name


########################################################
###  function for convert log level to numeric value ###
########################################################

function log_level_to_number {
	case "$1" in 
		DEBUG) echo 1 ;;
		INFO) echo 2 ;;
		WARN) echo 3 ;;
		ERROR) echo 4 ;;
		FATAL) echo 5 ;;
		*) echo 0 ;;
	esac
}

#################################################################
###  function for for generating log for different log levels ###
#################################################################

function print_log {
	local log_message=$1
	local log_level="${log_message%%]*}"
	log_level="${log_level#[}"

	###checking for log_dir existience 
	[[ ! -d $log_dir ]] && mkdir -p "$log_dir" && chmod 750 "$log_dir"

	### checking the log level is valid to generate log
	local msg_lvl_num=$(log_level_to_number "$log_level")
	local min_lvl_num=$(log_level_to_number "$min_log_level")
	if [ $msg_lvl_num -gt $min_lvl_num ]; then
		local cr_dt=$(date '+%Y%m%d')
		local cr_tm=$(date '+%Y%m%d %H:%M:%S')
		local pid=$$
		local log_file="$log_dir/$process_name.$cr_dt.log"
		local Message_format="$cr_tm [$pid] - $log_message"
		echo "$Message_format" >> $log_file
		return 0
	fi
}

###################################################################
###  function for handiling process hold or stop based on file  ###
###################################################################

function hold_stop_chk {
	PROCESS_NAME=$1
	hold_file="$HOLD_STOP_DIR/$PROCESS_NAME.HOLD"
	stop_file="$HOLD_STOP_DIR/$PROCESS_NAME.STOP"
	global_hold_file="$HOLD_STOP_DIR/GLOBAL.HOLD"
	global_stop_file="$HOLD_STOP_DIR/GLOBAL.STOP"
	HOLD=1
	while [ $HOLD -le 1 ]
	do
		if [ -f $hold_file ]; then
			print_log "[INFO] - Holding the process sleeping the process for $sleep_interval_HS"
			sleep $sleep_interval_HS
		else
			true $((HOLD=HOLD+1))
			print_log "[INFO] - $hold_file file not found"
		fi
		if [ -f $stop_file ]; then
			print_log "[INFO] - Stop file found $stop_file: Terminating the script"
			if ! rm -f "$stop_file" 2>/dev/null; then
				print_log "[ERROR] - failed to remove stop file \"$stop_file\". check permissions"
				return 1
			fi
			if ! rm -f "$hold_file" 2>/dev/null; then
                                print_log "[ERROR] - failed to remove hold file \"$hold_file\". check permissions"
                                return 1
                        fi
			
			exit
		fi
	done
        while [ $HOLD -le 1 ]
        do
                if [ -f $global_hold_file ]; then
                        print_log "[INFO] - Holding the process sleeping the process for $sleep_interval_HS"
                        sleep $sleep_interval_HS
                else
                        true $((HOLD=HOLD+1))
                        print_log "[INFO] - $global_hold_file file not found"
                fi
                if [ -f $global_stop_file ]; then
                        print_log "[INFO] - Stop file found $global_stop_file: Terminating the script"

                        exit
                fi
        done


}

###################################################################
############  function for creating serviceNow ticket   ###########
###################################################################

function serviceNow {
	### Below syntax for to get a function name ###
	#typeset function_name="${FUNCNAME[0]:-$0}"
	if [ $Ticket_flag = Y ]; then
		if [ $# -eq 4 ]; then
			Ticket_msg=$1
			Ticket_lvl=$2
			Team=$3
			Project=$4
			# `construct queary to generate ticket with $Ticket_msg $Ticket_lvl $Team $Project `
			STAT=$?
			if [ $STAT -eq 0 ]; then
				print_log "[INFO] - Ticket is generated"
				return 0
			else
				print_log "[ERROR] - ticket is not generated"
				return 1
			fi
		else
			print_log "[ERROR] - Invalid inputs, please provide Ticket_msg: , Ticket_lvl: , Team: , Project: , "
		fi
	else
		print_log "[INFO] - Ticket flag is not Y No ticket should created. "
		return 0
	fi
}

function get_checksum {
	#typeset function_name="${FUNCNAME[0]:-$0}"
	file_name="$1"

	if [ -f $file_name ]; then

		check_sum=`md5sum $file_name `
		STAT=$?
		if [ $STAT -eq 0 ]; then

			check_sum=`echo $check_sum | awk '{print $1}'`
			print_log "[INFO] - check sum generated for $file_name"
			return 0
		else
			print_log "[ERROR] - Failed to generated check sum value for $file_name"
			return 1
		fi
	else
		print_log "[error] - File \"$file_name\" does not exists "
		return 1
	fi

}
 

function convert_date {
	#typeset function_name="${FUNCNAME[0]:-$0}"
	Input_for=$1
	Input_value=$2
	Output_for=$3

	#validating input date format and input date value 
	IN_f_length="${#Input_for}"
	IN_v_length="${#Input_value}"
	
	set -A array "YYYYMMDD" "DDMMYYYY" "YYYY/MM/DD" "DD/MM/YYYY" "YYYY-MM-DD" "DD-MM-YYYY" "YYMMDD" "DDMMYY" "YY/MM/DD" "DD/MM/YY" "YY-MM-DD" "DD-MM-YY"
	for element in "${array[@]}"
	do
		if [ $Input_for == "$element" ]; then
			INFORMAT=GOOD
		break
		else
			INFORMAT=BAD
		fi
	done
        for element in "${array[@]}"
        do
                if [ $Output_for == "$element" ]; then
                        OUTFORMAT=GOOD
                break
                else
                        OUTFORMAT=BAD
                fi
        done

			


