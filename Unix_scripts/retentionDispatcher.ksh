#!/bin/ksh

PROCESSNAME=retentionDispatcher
cr_dt=`date '+%Y%m%d'`
cr_tm=`date '+%Y%m%d %H:%M:%S'`
prid=$$

ret_cfg="/e/UNIX/retentionDispatcher.cfg"
sharedmodule="/e/UNIX/common_module.ksh"
share_m_cfg="/e/UNIX/common_module.cfg"
Log_dir="/e/UNIX"

###### sourcing common module #############


if [ -s $sharedmodule ] && [ -s $share_m_cfg ]; then
	. $sharedmodule
	get_checksum "$sharedmodule"
	m3=$check_sum
	get_checksum "$share_m_cfg"
	m5=$check_sum

else
	echo "$cr_tm [$prid] - [ERROR] - The common module file $sharedmodule or config file $share_m_cfg is not found.Terminating the script ....." >> $Log_dir/retentionDispatcher.${cr_dt}.log
	exit
fi

##### sourcing retention dispatcher config file #####

if [ -s $ret_cfg ]; then
	.$ret_cfg
	get_checksum "$ret_cfg"
	m1=$check_sum
else
	print_log "[ERROR] - retention script config file $ret_cfg not found. Terminating the script....."
	exit
fi

##### checking retention Dispatcher process status #####

check_procstat "$PROCESSNAME"
if [ $? -eq 0 ]; then 
	print_log "[ERROR] - The process is already running Terminating the script"
	exit
fi

##### checking for input & output directories ####

[ ! -d "$rm_log" ] && mkdir -p "$rm_log" && chmod 750 "$rm_log"

if [ ! -d "$out_dir" ]; then
	print_log "[WARN] - $out_dir not exist, createing directory "
	mkdir -p $out_dir
	chmod 750 $out_dir
fi

if [ ! -d "$bad_dir" ]; then
	print_log "[WARN] - $bad_dir not exist, creating directory "
	mkdir -p $bad_dir
	chmod 750 $bad_dir
fi

if [ ! -d "$incoming_dir" ]; then
	print_log "[ERROR] - Incoming directory is not exist, Terminating the script.. "
	exit
fi

#####################################################################################
##### Function for checking config file update and for resourcing updated file ######
#####################################################################################

check_config() {

	######## checking for incoming directory ###########
	if [ ! -d $incomind_dir ]; then
		MESSAGE="[ERROR] - incoming directory \"$incoming_dir\" is not found. Terminating the script"
		print_log "$MESSAGE"
		echo "<tr><td style="text-align:right">MAIN SCRIPT</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
		fun_for_mail
		exit
	fi


	##### checking for any updates in config files #########

	get_checksum "$ret_cfg"
	m2="$check_sum"
	if [ $m1 != $m2 ]; then
		if [ ! -s $ret_cfg ]; then
			MESSAGE="[ERROR] - Retention dispatcher config file \"$ret_cfg\" not found terminating the script"
			print_log "$MESSAGE"
			echo "<tr><td style="text-align:right">MAIN SCRIPT</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
			fun_for_mail
			exit
		else
			print_log "[INFO] - Retention dispatcher config file \"$ret_cfg\" updated. Sourcing again"
			. $ret_cfg

			get_checksum "$ret_cfg"
			m1=$check_sum
		fi
	fi
	
	#### checking for common module ###

	get_checksum "$sharedmodule"
	m4=$check_cum
	get_checksum "$share_m_cfg"
	m6=$check_sum

	if [ $m3 != $m4 ] || [ $m5 != $m6 ]; then
		if [ ! -s $sharedmodule ]; then
			MESSAGE="[ERROR] - Common module file \" $sharedmodule\" not found. Terminating the script"
			print_log "$MESSAGE"
			echo "<tr><td style="text-align:right">MAIN SCRIPT</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
			fun_for_mail
			exit
		elif [ ! -s $share_m_cfg ]; then
                        MESSAGE="[ERROR] - Common module config file \" $share_m_cfg\" not found. Terminating the script"
                        print_log "$MESSAGE"
                        echo "<tr><td style="text-align:right">MAIN SCRIPT</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
                        fun_for_mail
                        exit
		else
			print_log "[INFO] - Common module script or config file updated. Sourcing common module again"

			. $sharedmodule

			get_checksum "$sharedmodule"
			m3=$check_sum
			get_checksum "$share_m_cfg"
			m5=$share_m_cfg
		fi

	fi
}

###############################################################
### Function for validating the no of segments of the file ####
###############################################################

fun_for_length() {

	file_length=`echo "$file_name" | awk -F"." '{print NF}'`
	case "$file_ext" in 
		targz)
			if [ $file_length = 8 ]; then
				print_log "[INFO] - $file_name valid in length calling next function for validating file extention"
				fun_for_ext
			else
				print_log "[ERROR] - file \"$file_path/$file_name\" is invalid in length, moving the file to bad directory \"$bad_dir\""
				fun_to_bad "file \"$file_path/$file_name\" is invalid in length, moving the file to bad directory \"$bad_dir\""
			fi;;
		*)
                        if [ $file_length = 7 ]; then
                                print_log "[INFO] - $file_name valid in length calling next function for validating file extention"
                                fun_for_ext
                        else
                                print_log "[ERROR] - file \"$file_path/$file_name\" is invalid in length, moving the file to bad directory \"$bad_dir\""
                                fun_to_bad "file \"$file_path/$file_name\" is invalid in length, moving the file to bad directory \"$bad_dir\""
                        fi;;
	esac
}



########################################################
##### Function for validating extention of the file ####
########################################################

fun_for_ext() {
	#set -A extent "eof" "del" "eod" "targz" "json" "EOF" "DEL" "EOD" "JSON"
	for element in "${extent[@]}";
	do
		EXT=$file_ext
		if [ "$EXT" = "$element" ]; then
			result=""
			print_log "[INFO] - file extention for \"$file_name\" is valid, proceeding for pair file"
			fun_for_pair
			break
		else
			result="Invalid"
		fi
	done
	if [ "$result" = "Invalid" ]; then
		print_log "[ERROR] - file extention for \"$file_path/$file_name\" is invalid, proceeding to rename file with .bad extention and moving to bad directory"
		fun_to_bad "file extention for \"$file_path/$file_name\" is invalid, proceeding to rename file with .bad extention and moving to bad directory"
	fi
}


###################################################################
##### Function for Validating matching pair file of the file  #####
###################################################################

fun_for_pair() {
	case "$file_ext" in 
		del)
			pair_format_lc=$(echo "$file_name" | sed 's/\.del$/.eof/')
			pair_format_uc=$(echo "$file_name" | sed 's/\.del$/.EOF/')
			if [ -f $file_path/$pair_format_lc ]; then 
				pairfile=$pair_format_lc
				Pattern="Y"
			elif [ -f $file_path/$pair_format_uc ]; then
				pairfile=$pair_format_uc
				Pattern="Y"
			else
				Pattern="NA"
			fi

			if [ "$Pattern" = "Y" ]; then
				if [ $Appname = "SEED" ]; then
					fun_for_seed
				else
					print_log "[INFO] - file pair for $file_name is $pairfile  found, proceeding for record count validation"
					fun_for_recon
				fi
			elif [ "$Pattern" = "NA" ]; then
				fun_for_sla
				if [ "$file_time" -le "$DELSLA" ]; then
					print_log "[INFO] - for file $file_name pair file not found and not reaching to SLA. will check for pair in next run"
				else
					print_log "[ERROR] - for file $file_name pair file not found and reaching to SLA. moving the file to bad directory\"$bad_dir\""
					fun_to_bad "[ERROR] - for file $file_name pair file not found and reaching to SLA. moving the file to bad directory\"$bad_dir\""
				fi
			fi;;

                eof)
                        pair_format_lc=$(echo "$file_name" | sed 's/\.eof$/.del/')
                        pair_format_uc=$(echo "$file_name" | sed 's/\.eof$/.DEL/')
                        if [ -f $file_path/$pair_format_lc ]; then
                                pairfile=$pair_format_lc
                                Pattern="Y"
                        elif [ -f $file_path/$pair_format_uc ]; then
                                pairfile=$pair_format_uc
                                Pattern="Y"
                        else
                                Pattern="NA"
                        fi

                        if [ "$Pattern" = "Y" ]; then
                                if [ $Appname = "SEED" ]; then
                                        fun_for_seed
                                else
                                        print_log "[INFO] - file pair for $file_name is $pairfile  found, proceeding for record count validation"
                                        fun_for_recon
                                fi
                        elif [ "$Pattern" = "NA" ]; then
                                fun_for_sla
                                if [ "$file_time" -le "$DELSLA" ]; then
                                        print_log "[INFO] - for file $file_name pair file not found and not reaching to SLA. will check for pair in next run"
                                else
                                        print_log "[ERROR] - for file $file_name pair file not found and reaching to SLA. moving the file to bad directory\"$bad_dir\""
                                        fun_to_bad "[ERROR] - for file $file_name pair file not found and reaching to SLA. moving the file to bad directory\"$bad_dir\""
                                fi
                        fi;;


                targz)
                        pair_format_lc=$(echo "$file_name" | sed 's/\.tar.gz$/.eod/')
                        pair_format_uc=$(echo "$file_name" | sed 's/\.tar.gz$/.EOD/')
                        if [ -f $file_path/$pair_format_lc ]; then
                                pairfile=$pair_format_lc
                                Pattern="Y"
                        elif [ -f $file_path/$pair_format_uc ]; then
                                pairfile=$pair_format_uc
                                Pattern="Y"
                        else
                                Pattern="NA"
                        fi

                        if [ "$Pattern" = "Y" ]; then
                                if [ $Appname = "SEED" ]; then
                                        fun_for_seed
                                else
                                        print_log "[INFO] - file pair for $file_name is $pairfile  found, proceeding for record count validation"
                                        fun_for_tar
                                fi
                        elif [ "$Pattern" = "NA" ]; then
                                fun_for_sla
                                if [ "$file_time" -le "$DELSLA" ]; then
                                        print_log "[INFO] - for file $file_name pair file not found and not reaching to SLA. will check for pair in next run"
                                else
                                        print_log "[ERROR] - for file $file_name pair file not found and reaching to SLA. moving the file to bad directory\"$bad_dir\""
                                        fun_to_bad "[ERROR] - for file $file_name pair file not found and reaching to SLA. moving the file to bad directory\"$bad_dir\""
                                fi
                        fi;;


                eod)
			pair_format_lc=$(echo "$file_name" | sed 's/\.eod$/.tar.gz/')
                        if [ -f $file_path/$pair_format_lc ]; then
                                pairfile=$pair_format_lc
                                Pattern="Y"
                        else
                                Pattern="NA"
                        fi

                        if [ "$Pattern" = "Y" ]; then
                                if [ $Appname = "SEED" ]; then
                                        fun_for_seed
                                else
                                        print_log "[INFO] - file pair for $file_name is $pairfile  found, proceeding for record count validation"
                                        fun_for_tar
                                fi
                        elif [ "$Pattern" = "NA" ]; then
                                fun_for_sla
                                if [ "$file_time" -le "$DELSLA" ]; then
                                        print_log "[INFO] - for file $file_name pair file not found and not reaching to SLA. will check for pair in next run"
                                else
                                        print_log "[ERROR] - for file $file_name pair file not found and reaching to SLA. moving the file to bad directory\"$bad_dir\""
                                        fun_to_bad "[ERROR] - for file $file_name pair file not found and reaching to SLA. moving the file to bad directory\"$bad_dir\""
                                fi
                        fi;;

		esac
	}


################################################################################
###### Function for validating the record count of the file & pair file ########
################################################################################

fun_for_recon() {
	case "$file_ext" in 
		del|DEL)

			LINE_C=$(sed -n '$=' $file_path/$file_name)
			A_LINE_C=$(($LINE_C - 1))
			grep ":" $file_path/$pairfile
			if [ $? -eq 0 ]; then
				COUN=$(cat $file_path/$pairfile | awk -F":" '{print $1}')
			else 
				COUN=$(cat $file_path/$pairfile)
			fi
			if [ $A_LINE_C -eq $COUN ]; then
				print_log "[INFO] - for the file $file_name and pair file $pairfile the count is matching proceeding to next process"
				fun_for_archive
			else
				print_log "[ERROR] - for the file $file_name and pair file $pairfile the count is not matching moving the files to bad directory $bad_dir"
				fun_for_pairbad "[ERROR] - for the file $file_name and pair file $pairfile the count is not matching moving the files to bad directory $bad_dir"
			fi;;

		eof|EOF)
                        LINE_C=$(sed -n '$=' $file_path/$pairfile)
                        A_LINE_C=$(($LINE_C - 1))
                        grep ":" $file_path/$file_name
                        if [ $? -eq 0 ]; then
                                COUN=$(cat $file_path/$file_name | awk -F":" '{print $1}')
                        else
                                COUN=$(cat $file_path/$file_name)
                        fi
                        if [ $A_LINE_C -eq $COUN ]; then
                                print_log "[INFO] - for the file $file_name and pair file $pairfile the count is matching proceeding to next process"
                                fun_for_archive
                        else
                                print_log "[ERROR] - for the file $file_name and pair file $pairfile the count is not matching moving the files to bad directory $bad_dir"
                                fun_for_pairbad "[ERROR] - for the file $file_name and pair file $pairfile the count is not matching moving the files to bad directory $bad_dir"
                        fi;;
		esac
	}
 
#####################################################################################################
####### Function for Validting the tar.gz file and eod file and to decompress the tar file ##########
#####################################################################################################


fun_for_tar() {
	case "$file_ext" in 
		targz)
			LINE_C=$(gunzip -c $file_path/$file_name | tar tf - | wc -l)
			ALINE_C=$(($LINE_C/2))
			grep ":" $file_path/$file_name
			if [ $? -eq 0 ]; then
				COUN=$(cat $file_path/$file_name | awk -F":" '{print $1}')
			else
				COUN=$(cat $file_path/$file_name)
			fi
			if [ $A_LINE_C -eq $COUN ]; then
			   if [ $Sor = "COMPRESS" || $SOr = "compress" || $Sor = "Compress" ]; then
				print_log "[INFO] - Pair files belongs to COMPRESS, need to send \"tar.gz\" and \"eod\" files to outgoing directory"
				print_log "[INFO] - for file $file_name and pairfile $pairfile the count is matching, proceeding for next process "
				fun_for_archive
			   else
				print_log "[INFO] - for file $file_name and pairfile $pairfile the count is matching decompressing the gz file and removing tar file and eod file"
				gzip -d $file_path/$file_name
				tar_file=$(echo $file_name | sed 's/\.gz$//')
				cd $file_path 
				tar -xvf $tar_file
				if [ $? -eq 0 ]; then
					print_log "[INFO] - Untar the tar.gz file completed at \"$file_path\", deleting the $tar_file and $pairfile"
					if ! rm -f "$tar_file" 2>/dev/null; then
						MESSAGE="[ERROR] - Failed to remove $tar_file at $file_path. Chech permissions"
						print_log "$MESSAGE"
						echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
					else
						if rm -f "$pairfile" 2>dev/null; then
							set -A PDFile "${PDFile[@]}" "$file_path/$pair_file"
							print_log "[INFO] - Deleting the $tar_file and $pairfile is completed"
						else
							Message "[ERROR] - Failed to remove $pairfile. check permissions"
							print_log "$MESSAGE"
							echo "<tr><td style="text-align:right">$file_path/$pairfile</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
						fi
					fi
				else
					gzip $tar_file
					MESSAGE="[ERROR] - Untar the tar.gz file is failed for \"$tar_file\" file $file_path/$file_name and $pairfile is in incoming directory"
					echo "<tr><td style="text-align:right"> $file_path/$tar_file</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
					print_log "$MESSAGE"
				fi
				cd $incoming_dir
			   fi
			else
			   if [ $Sor = "COMPRESS" || $SOr = "compress" || $Sor = "Compress" ]; then
                                print_log "[INFO] - Pair files belongs to COMPRESS, need to send \"tar.gz\" and \"eod\" files to outgoing directory"
				print_log "[ERROR] - for file \"$file_path/$file_name\" and pair file \"$file_path/$pairfile\" the count is not matching, moving the pair files to bad directory \"$bad_dir\" "
				fun_to_pairbad "for file \"$file_path/$file_name\" and pair file \"$file_path/$pairfile\" the count is not matching, moving the pair fi
les to bad directory \"$bad_dir\" "
			   else
				print_log "[ERROR] - for file \"$file_path/$file_name\" and pair file \"$file_path/$pairfile\" the count is not matching inziping the tar file and moving the files to bad directory \"$bad_dir\" "
				gzip -d $file_path/$file_name
				tar_file=$(echo "$file_name" | sed 's/\gz$//')
				cd $file_path
				tar -xvf $tar_file
				if [$? -eq 0 ]; then 
					print_log "[INFO] - Untar the tar.gz file completed at \"$file_path\", moving the $tar_file and $pairfile to bad directory $bad_dir "
					pfile_name=$file_name
					file_name=$tar_file
					fun_to_pairbad "for file $file_path/$pfile_name and pairfile $file_path/$pairfile the count is not matching, untaring the file is completed. Tar.gz file contains \"$A_LINE_C\" pair files and .eod file contains \"$COUN\" pair file \n Please provide remaining pair files"
				else
					gzip $tar_file
					MESSAGE="[ERROR] - for file $file_path/$file_name and pairfile $file_path/$pairfile the count is not matching, Unable to untar the file"
					echo "<tr><td style="text-align:right"> $file_path/$tar_file</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
                                        print_log "$MESSAGE"
                                fi
                                cd $incoming_dir
                           fi
			fi;;


		eod|EOD)
                        LINE_C=$(gunzip -c $file_path/$pairfile | tar tf - | wc -l)
                        ALINE_C=$(($LINE_C/2))
                        grep ":" $file_path/$file_name
                        if [ $? -eq 0 ]; then
                                COUN=$(cat $file_path/$file_name | awk -F":" '{print $1}')
                        else
                                COUN=$(cat $file_path/$file_name)
                        fi
                        if [ $A_LINE_C -eq $COUN ]; then
                           if [ $Sor = "COMPRESS" || $SOr = "compress" || $Sor = "Compress" ]; then
                                print_log "[INFO] - Pair files belongs to COMPRESS, need to send \"tar.gz\" and \"eod\" files to outgoing directory"
                                print_log "[INFO] - for file $file_name and pairfile $pairfile the count is matching, proceeding for next process "
                                fun_for_archive
                           else
                                print_log "[INFO] - for file $file_name and pairfile $pairfile the count is matching decompressing the gz file and removing tar file and eod file"
                                gzip -d $file_path/$pairfile
                                tar_file=$(echo $pairfile | sed 's/\.gz$//')
                                cd $file_path
                                tar -xvf $tar_file
                                if [ $? -eq 0 ]; then
                                        print_log "[INFO] - Untar the tar.gz file completed at \"$file_path\", deleting the $tar_file and $file_nmae"
                                        if ! rm -f "$tar_file" 2>/dev/null; then
                                                MESSAGE="[ERROR] - Failed to remove $tar_file at $file_path. Chech permissions"
                                                print_log "$MESSAGE"
                                                echo "<tr><td style="text-align:right">$file_path/$tar_file</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
                                        else
                                                if rm -f "$file_name" 2>dev/null; then
                                                        set -A PDFile "${PDFile[@]}" "$file_path/$pairfile"
                                                        print_log "[INFO] - Deleting the $tar_file and $pairfile is completed"
                                                else
                                                        Message "[ERROR] - Failed to remove $file_name. check permissions"
                                                        print_log "$MESSAGE"
                                                        echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
                                                fi
                                        fi
                                else
                                        gzip $tar_file
                                        MESSAGE="[ERROR] - Untar the tar.gz file is failed for \"$tar_file\" file $file_path/$file_name and $pairfile is in incoming directory"
                                        echo "<tr><td style="text-align:right"> $file_path/$tar_file</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
                                        print_log "$MESSAGE"
                                fi
                                cd $incoming_dir
                           fi
                        else
                           if [ $Sor = "COMPRESS" || $SOr = "compress" || $Sor = "Compress" ]; then
                                print_log "[INFO] - Pair files belongs to COMPRESS, need to send \"tar.gz\" and \"eod\" files to outgoing directory"
                                print_log "[ERROR] - for file \"$file_path/$file_name\" and pair file \"$file_path/$pairfile\" the count is not matching, moving the pair files to bad directory \"$bad_dir\" "
                                fun_to_pairbad "for file \"$file_path/$file_name\" and pair file \"$file_path/$pairfile\" the count is not matching, moving the pair fi
les to bad directory \"$bad_dir\" "
                           else
                                print_log "[ERROR] - for file \"$file_path/$file_name\" and pair file \"$file_path/$pairfile\" the count is not matching unziping the tar file and moving the files to bad directory \"$bad_dir\" "
                                gzip -d $file_path/$pairfile
                                tar_file=$(echo "$pairfile" | sed 's/\gz$//')
                                cd $file_path
                                tar -xvf $tar_file
                                if [$? -eq 0 ]; then
                                        print_log "[INFO] - Untar the tar.gz file completed at \"$file_path\", moving the $tar_file and $file_name to bad directory $bad_dir "
                                        ppairfile=$pairfile
                                        pairfile=$tar_file
                                        fun_to_pairbad "for file $file_path/$file_name and pairfile $file_path/$ppairfile the count is not matching, untaring the file is completed. Tar.gz file contains \"$A_LINE_C\" pair files and .eod file contains \"$COUN\" pair file \n Please provide remaining pair files"
                                else
                                        gzip $tar_file
                                        MESSAGE="[ERROR] - for file $file_path/$file_name and pairfile $file_path/$pairfile the count is not matching, Unable to untar the file"
                                        echo "<tr><td style="text-align:right"> $file_path/$pairfile</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
                                        print_log "$MESSAGE"
                                fi
                                cd $incoming_dir
                           fi
                        fi;;
		esac
}


###########################################################
### Function for copying both pair files to respective ####
### Outgoing directory and move files to rm-log dir    ####
###########################################################

fun_for_archive() {
	case $Appname in 

		RETNEVENT)

			RET="RET_EVENT_SOR"
			connect_db
			if [ $? -eq 0 ]; then
				DBOP=`db2 -x "select count (distinct $ARCHIVE) from $ARCHIVE_TABLE where $RET = '$Sor'"`
				STAT=$?
				if [ $STAT -eq 0 ] && [ $DBOP -eq 0 ]; then
					MESSAGE="[ERROR] - Zero records found for $ARCHIVE for app name \"$RET\" and for SOR \"$Sor\" moving both pair files to rm_log"
					print_log "$MESSAGE"
					echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
					if [ -d $rm_log ]; then
						fun_for_move "$file_path/$pairfile" "$rm_log/$pairfile"
						if [ $MOVE -eq 4 ]; then
							set -A PDfile "${PDfile[@]}" "$file_path/$pairfile"
							fun_for_move "$file_path/$file_name" "$rm_log/$file_name"
						fi
					else
						MESSAGE="[ERROR] - Moving Pair file to rm-log directory \"$rm_log\" is not initiated. The directory does not exists"
						print_log "$MESSAGE"
						echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
					fi
				elif [ $STAT -eq 0 ] && [ $DBOP -ne 0 ]; then
					db2 -x "select distinct $ARCHIVE from $ARCHIVE_TABLE where $RET = '$Sor'" > $Arch_file
					if [ ! -s $Arch_file ];then
						MESSAGE="[ERROR] - Failed to fetch $ARCHIVE details from DATABASE, Pair files are not copied to outgoing Archive directories" 
						print_log "$MESSAGE"
						echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
					else
						print_log "[INFO] - $ARCHIVE detaing are fetched successfully from DATABASE, Copying Pair files to respective outgoing directories"
						fun_to_copy
					fi
				else
					MESSAGE="[ERROR] - db2 sql query is failed to fetch $ARCHIVE details from $ARCHIVE_TABLE, Pair files are not copied to out going directories"
					print_log "$MESSAGE"
					echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
				fi
				db2 terminate
			else
				MESSAGE="[ERROR] - db connection failed, unable to copy pair files to out going directories"
				print_log "$MESSAGE"
				echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
			fi;;

		HOLDS-EVENTS)
			RET="RET_HOLD_SOR"
                        connect_db
                        if [ $? -eq 0 ]; then
                                DBOP=`db2 -x "select count (distinct $ARCHIVE) from $ARCHIVE_TABLE where $RET = '$Sor'"`
                                STAT=$?
                                if [ $STAT -eq 0 ] && [ $DBOP -eq 0 ]; then
                                        MESSAGE="[ERROR] - Zero records found for $ARCHIVE for app name \"$RET\" and for SOR \"$Sor\" moving both pair files to rm_log"
                                        print_log "$MESSAGE"
                                        echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
                                        if [ -d $rm_log ]; then
                                                fun_for_move "$file_path/$pairfile" "$rm_log/$pairfile"
                                                if [ $MOVE -eq 4 ]; then
                                                        set -A PDfile "${PDfile[@]}" "$file_path/$pairfile"
                                                        fun_for_move "$file_path/$file_name" "$rm_log/$file_name"
                                                fi
                                        else
                                                MESSAGE="[ERROR] - Moving Pair file to rm-log directory \"$rm_log\" is not initiated. The directory does not exists"
                                                print_log "$MESSAGE"
                                                echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
                                        fi
                                elif [ $STAT -eq 0 ] && [ $DBOP -ne 0 ]; then
                                        db2 -x "select distinct $ARCHIVE from $ARCHIVE_TABLE where $RET = '$Sor'" > $Arch_file
                                        if [ ! -s $Arch_file ];then
                                                MESSAGE="[ERROR] - Failed to fetch $ARCHIVE details from DATABASE, Pair files are not copied to outgoing Archive directories"
                                                print_log "$MESSAGE"
                                                echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_M
SG
                                        else
                                                print_log "[INFO] - $ARCHIVE detaing are fetched successfully from DATABASE, Copying Pair files to respective outgoing direc
tories"
                                                fun_to_copy
                                        fi
                                else
                                        MESSAGE="[ERROR] - db2 sql query is failed to fetch $ARCHIVE details from $ARCHIVE_TABLE, Pair files are not copied to out going dir
ectories"
                                        print_log "$MESSAGE"
                                        echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
                                fi
                                db2 terminate
                        else
                                MESSAGE="[ERROR] - db connection failed, unable to copy pair files to out going directories"
                                print_log "$MESSAGE"
                                echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
                        fi;;
		*)
			print_log "[ERROR] - APP name $Appname is not vaild moving pair files \"$file_path/$file_name\" & \"$pairfile\" to bad directory"
			fun_to_pairbad "APP name $Appname is not vaild moving pair files \"$file_path/$file_name\" & \"$pairfile\" to bad directory"
	esac
}


##########################################
####  Function for SLA Validation ########
##########################################

fun_for_sla() {

	file_intime=$(ls -l "$file_path/$file_name" | awk '{print $6, $7, $8}')
	DATE=$(date '+%b %d %H:%M')
	file_epoch=$(perl -MTime::Piece -e "print Time::Piece->strptime('$file_intime', '%b %d %H:%M')->epoch")
	DATE_epoch=$(perl -MTime::Piece -e "print Time::Piece->strptime('$DATE', '%b %d %H:%M')->epoch")
	file_time=$((DATE_epoch - file_epoch))

}


###########################################################
### Function for moving SEED files to rm-log directory ####
###########################################################

fun_for_SEED() {

	print_log "[INFO] - The file \"$file_path/$file_name\" and pair file has app name is SEED \"$Appname\", Moving pair file to rm-log directory"
	if [ -d $rm_log ]; then
        	fun_for_move "$file_path/$pairfile" "$rm_log/$pairfile"
                if [ $MOVE -eq 4 ]; then
                        set -A PDfile "${PDfile[@]}" "$file_path/$pairfile"
                	fun_for_move "$file_path/$file_name" "$rm_log/$file_name"
        	fi
        else
                MESSAGE="[ERROR] - Moving Pair file to rm-log directory \"$rm_log\" is not initiated. The directory does not exists"
                print_log "$MESSAGE"
        	echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
	fi
}


################################################################
#####   Function for moving the files from one path to other ###
################################################################

fun_for_move() {

	IN_path=$1
	Out_path=$2
	MOVE=1
	while [ $MOVE -le 2 ] 
	do
		mv $IN_path $Out_path
		if [ $? -eq 0 ]; then
			print_log "[INFO] - Moving the file from $IN_path to \"$Out_path\" is completed"
			MOVE=4
		else
			if [ -f $IN_path ]; then
				print_log "[ERROR] - Moving the file from \"$IN_path\" to \"$Out_path\" is failed. Files \"$IN_path\" exists."
				MOVE=$(($MOVE+1))
				sleep $M_SLEEP
			else
				print_log "[ERROR] - Moving the file from \"$IN_path\" to \"$Out_path\" is failed. Files \"$IN_path\" is not exists"
				MOVE=5
			fi
		fi
	done
	case "$MOVE" in 
		5) 
			MESSAGE="[ERROR] - Moving the file from \"$IN_path\" to \"$Out_path\" is failed. Files \"$IN_path\" is not exists."
			echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
		3)
			MESSAGE="[ERROR] - Moving the file from \"$IN_path\" to \"$Out_path\" is failed. Files \"$IN_path\" exists."
			echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
	esac
}

#########################################################################
#### Function for copying Pair files to Out going Archive directories ###
#########################################################################

fun_to_copy() {
	set -A copiedfiles
	for ARCH in $(cat $Arch_file);
	do
		[[ ! -d "$Out_dir/$ARCH" ]] && mkdir -p "$Out_dir/$ARCH" && chmod -R 755 "$Out_dir/$ARCH"
		if ! cp "$file_path/$file_name" "$Out_dir/$ARCH/$file_name.tmp" 2>/dev/null; then
			MESSAGE="[ERROR] - Failed to copy $file_name to \"$Out_dir/$ARCH\" with .tmp extention, check permissions."
			print_log "$MESSAGE"
			copy_failed "$MESSAGE"
			COPYSTAT=N
			break
		else
			set -A copiedfiles "${copiedfiles[@]}" "$Out_dir/$ARCH/$file_name.tmp"
			if cp"$file_path/$pairfile" "$Out_dir/$ARCH/$pairfile.tmp" 2>/dev/null; then
				print_log "[INFO] - Copying Pair files from \"$file_path\" to \"$Out_dir/$ARCH\" with .tmp extention is completed."
				set -A copiedfiles "${copiedfiles[@]}" "$Out_dir/$ARCH/$pairfile.tmp"
				COPYSTAT=Y
			else
				MESSAGE="[ERROR] - Failed to copy $pairfile to \"$Out_dir/$ARCH\" with .tmp extention, check permissions."
	                        print_log "$MESSAGE"
        	                copy_failed "$MESSAGE"
                	        COPYSTAT=N
                        	break
			fi
		fi
	done
	[[ $COPYSTAT = Y ]] && fun_for_rename
}

###############################################################################################
#### Function for removing .tmp files. If files are partially copied to outgoing directory ####
###############################################################################################

copy_failed() {
	MSG=$1
	for TEMPfile in "${copiedfiles[@]}";
	do
		if ! rm -f "$TEMPfile" 2>/dev/null; then
			print_log "[ERROR] - Failed to remove $TEMPfile file. check permissions"
		else
			print_log "[INFO] - Temporary file \"$TEMPfile\" removed successfully"
		fi
	done
	echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MSG</td></tr>" >> $ERR_MSG
	set -A copiedfiles
}



##########################################################################################
#### Function for renaming .tmp file which are copied to outgoing Archive directories ####
##########################################################################################

fun_for_rename() {

	set -A renamedfiles
	for TEMPfile in "${copiedfiles[@]}";
	do
		ACTFile=`echo $TEMPfile | sed 's/\.tmp$//'`
		fun_for_move "$TEMPfile" "$ACTFile"
		if [ $MOVE -eq 4 ]; then
			print_log "[INFO] - Renaming $TEMPfile to $ACTFile is completed"
			set -A renamedfiles "${renaedfiles[@]}" "$ACTFile"
			RENAMESTAT=Y
		else
			RENAMESTAT=N
			break
		fi

	done

	if [ $RENAMESTAT = Y ]; then
		set -A copiedfiles
		set -A renamedfiles
		print_log "[INFO] - Pair files \"$file_path/$file_name\" and \"$pairfile\" are successfully copied to all respective outgoing directories. Moving pair files to rm_log"
		fun_for_move "$file_path/$pairfile" "$rm_log/$pairfile"
		if [ $MOVE -eq 4 ]; then
			set -A PDFile "${PDFile[@]}" "$file_path/$pairfile"
			fun_for_move "$file_path/$file_name" "$rm_log/$file_name"
		fi
		if ! rm -f "$Arch_file" 2>/dev/null; then
			print_log "[ERROR] - Failed to remove $Arch_file file. check permissions"
		fi
	elif [ $RENAMESTAT = N ]; then
		MESSAGE="[ERROR] - Renaming the Temporary file having .tmp entention in outgoing Archive directories is failed for \"$file_name\" and \"$pairfile\". Removing renamed files"
		print_log "$MESSAGE"
		echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG

		for Rfile in "${renamedfiles[@]}";
		do
			if ! rm -f "$Rfile" 2>/dev/null; then
				MESSAGE="[ERROR] - Failed to remove $Rfile file. check permissions"
				print_log "$MESSAGE"
				echo "<tr><td style="text-align:right">$Rfile</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
			else
				print_log "[INFO] - Renamed $Rfile file removed successfully"
			fi
		done

		for RTEMfile in "${copiedfiles[@]}";
		do
			if [ -f "$RTEMPfile" ]; then
				if ! rm -f "$RTEMPfile" 2>/dev/null; then
                                	MESSAGE="[ERROR] - Failed to remove $RTEMPfile file. check permissions"
                                	print_log "$MESSAGE"
                                	echo "<tr><td style="text-align:right">$RTEMPfile</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
                        	else
                                	print_log "[INFO] - Renamed $RTEMPfile file removed successfully"
                        	fi
			fi
                done

		set -A copiedfiles
		set -A renamedfiles
                if ! rm -f "$Arch_file" 2>/dev/null; then
                        print_log "[ERROR] - Failed to remove $Arch_file file. check permissions"
                fi
	fi

}



##########################################
#### Function for HTML body formation ####
##########################################

fun_for_mail() {

	echo 'Content-Type: text/html' > $BODY_file
	echo 'Content-Disposition: inline' >> $BODY_file
	echo '<!DOCTYPE html>' >> $BODY_file
	echo '<html>' >> $BODY_file
	echo '<head>' >> $BODY_file
	echo '<style>' >> $BODY_file
	echo 'table, th, td {' >> $BODY_file
	echo '	border: 2px solid black;' >> $BODY_file
	echo '	border-collapse: colapse;' >> $BODY_file
	echo '}' >> $BODY_file
	echo 'th { padding: 4px; text-align: center; font-family: Calibri; font-size: 10pt; }' >> $BODY_file
	echo 'td { padding: 2px: text-align: left; font-family: Calibri; font-size: 10pt; }' >> $BODY_file
	echo 'p { font-family:verdana; font-size: 10pt; }' >> $BODY_file
	echo '</style>' >> $BODY_file
	echo '</head>' >> $BODY_file
	echo '' >> $BODY_file
	echo '<p>Hi Team,</p>' >> $BODY_file
	echo '<p>Critical</p>' >> $BODY_file
	echo '<p></p>' >> $BODY_file
	echo '<p> In Retention Dispatcher file processing, there is a failure, Please find below listed files with a ERROR message.</p>' >> $BODY_file
	echo '' >> $BODY_file
	echo '<table>' >> $BODY_file
	echo '<colgrop>' >> $BODY_file
	echo '<col span="1" style="background-color:red">' >> $BODY_file
	echo '<col style="background-color:yellow">' >> $BODY_file
	echo '</colgrop>' >> $BODY_file
	echo '<tr>' >> $BODY_file
	echo '<th style="background-color:#FF0000"> File Name </th>' >> $BODY_file
	echo '<th style="background-color:#FF0000"> Error Message </th>' >> $BODY_file
	echo '</tr>' >> $BODY_file
	cat $ERR_MSG >> $BODY_file
	echo '</table>' >> $BODY_file
	echo '<p></p>' >> $BODY_file
	echo '<p></p>' >> $BODY_file
	echo '<p>Thank you</p>' >> $BODY_file
	echo '<p>PROD-SUPORT</p>' >> $BODY_file
	echo '</body>' >> $BODY_file
	echo '</html>' >> $BODY_file

	if [ $MAIL_FLAG == "Y" ]; then
		send_mail "$BODY_file" "${ENVR}:${HOST}-Rentention Dispatcher Failure on ${cr_tm}" "N"
	fi
	sed 's/<tr><td style=text-align:right>//; s/<\/td>//g; s/<td style=text-align:right>/ - /; s/<\/tr>//g' $ERR_MSG > $ERROR_MESSAGE

	if ! rm -f "$BODY_file" "$ERR_MSG" 2>/dev/null; then
		print_log "[ERROR] -Failed to remove $BODY_file & $ERR_MSG files. Check permissions"
	fi

	if [ $SNOW_FLAG == "Y" ]; then
		create_snow "${ENVR}:${HOST}-Rentention Dispatcher Failure on ${cr_tm} - ERROR log ${ERROR_MESSAGE}" "WARNING" "APPLICATION/ONDEMAND/EXTRACT FAIL/ERRR" "C3OPTDMONDEMAND"
	fi
}



#########################################################
### Function for moving Invalid file to BAD directory ###
#########################################################

fun_to_bad() {

	MESSAGE=$1
	echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
	if [ -d $bad_dir ]; then
		fun_for_move "$file_path/$file_name" "$bad_dir/$file_name.bad"
	else
		MESSAGE="[ERROR] - Moving Invalid file to $bad_dir is not initiated. The $bad_dir directory does not exists"
		print_log "$MESSAGE"
		echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
		
	fi

}

##############################################################
### Function for moving Invalid pair file to BAD directory ###
##############################################################

fun_to_pairbad() {

        MESSAGE=$1
        echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
        if [ -d $bad_dir ]; then
                fun_for_move "$file_path/$pairfile" "$bad_dir/$pairfile.bad"
		if [ $MOVE -eq 4 ]; then
			set -A PDFile "${PDFile[@]}" "$file_path/$pairfile"
			fun_for_move "$file_path/$file_name" "$bad_dir/$file_name.bad"
		fi
        else
                MESSAGE="[ERROR] - Moving Invalid file to $bad_dir is not initiated. The $bad_dir directory does not exists"
                print_log "$MESSAGE"
                echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG

        fi

}



########################################################## MAIN Script ##################################################################
# For evenry File within the sub-directory of Incoming directory will perform the below steps recursively

while [[ "$EXIT_FLAG" -eq 1 ]];
do
	#### check_config will check for any updates in config and sourse respective file if there is any updates
	check_config

	######check for HOLD and SHUTDOWN files
	hold_stop_chk "$PROCESS"

	cd $incoming_dir
	MESSAGE=""
	for sub_dir in `ls -l | grep '^d' | awk '{print $9}'`;
	do
		if [ ! -d $incoming_dir/$sub_dir ]; then
			MESSAGE="[ERROR] - The directory \"$incoming_dir/$sub_dir\" is Missing"
			print_log "$MESSAGE"
			echo "<tr><td style="text-align:right">$incoming_dir/$sub_dir</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
			continue
		fi
		set -A PDFile
		for file_name in `ls -l $incoming_dir/$sub_dir | awk '{print $9}'`;
		do
			file_path="$incoming_dir/$sub_dir"
			if [ -f $file_path/$file_name ]; then
				file_ext=`echo $file_name | awk -F"." '{print $7 $8 $9}'`
				file_prefix=`echo $file_name | awk -F'.' '{NF--; print $0}' OFS=.`
				Appname=`echo $file_name | awk -F"." '{print $4}'`
				Sor=`echo $file_name | awk -F"." '{print $3}'`
				print_log "[INFO] - for the file \"$file_name\" at \"$file_path\" proceeding for length validation"
				fun_for_length
			else
				if [ ! -f $file_path/$file_name ]; then
					for FILE in "${PDFile[@]}"; 
					do
						if [ "$file_path/$file_name" = "$FILE" ]; then
							PSTAT=Y
							print_log "[INFO] - the file \"$file_path/$file_name\" is already processed"
							break
						else
							PSTAT=N
						fi
					done
					if [ $PSTAT = N ]; then
						MESSAGE="[ERROR] - The file \"$file_path/$file_name\" is Missing "
						print_log "$MESSAGE"
						echo "<tr><td style="text-align:right">$file_path/$file_name</td> <td style="text-align:right">$MESSAGE</td></tr>" >> $ERR_MSG
					fi
				fi
			fi
		done
	done

	if [ ${#MESSAGE} -gt 0 ]; then
		fun_for_mail
	fi

	sleep $SLEEP_INV
done





