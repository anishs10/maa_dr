#!/bin/bash

## dg_setup_scripts version 1.0.
##
## Copyright (c) 2022 Oracle and/or its affiliates
## Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
##

# CONSIDERATIONS:
# 1.-THIS SCRIPT MUST BE EXECUTED BY THE "root" USER IN THE SECONDARY DATABASE NODE(S)
# 2.-THIS SCRIPT PREPARES THE SECONDARY SYSTEM AND CREATES A DATAGUARD CONFIGURATION
# 3.-IF RAC, RUN FIRST IN THE NODE1 AND THEN IN THE NODE2
# 4.-THIS SCRIPT NEEDS THE LOCATION OF THE OUTPUT TAR FILES GENERATED BY 2_dataguardit_primary.sh
# 5.-THIS SCRIPT LOADS THE ENV VARIABLES FROM DG_properties.ini FILE
# 6.-THIS SCRIPT DOES NOT PERFORM OS CHANGES LIKE net.core.rmem_max and net.core.wmem_max or MTU. REFER TO THE MAA PAPERS TO SET THESE 
# 	(IT IS A BEST PRACTICE TO ADJUST net.core.rmem_max and net.core.wmem_max FOR OPTIMUM REDO TRASNPORT)

# Check that this is running by oracle root
if [ "$(whoami)" != "root" ]; then
        echo "Script must be run as user: root"
        exit 1
fi

########################################################################
# Load environment specific variables
########################################################################
if [ -f DG_properties.ini ]; then
        . DG_properties.ini
else
        echo "ERROR: DG_properties.ini not found"
        exit 1
fi


########################################################################################
# Variables with fixed or dynamically obtained values
#########################################################################################
export dt=$(date +%Y-%m-%d-%H_%M_%S)
. /home/${ORACLE_OSUSER}/.bashrc

if [ -z "$ORACLE_HOME" ]; then
        echo "Error: the ORACLE_HOME variable is not defined in oracle user's env"
        exit 1
fi

if [ -f "${ORACLE_HOME}/bin/orabasehome" ]; then
        # Since 18c, base home maybe used. In 21c base home is the only option
	# Getting TNS admin AND OTHER FOLDES dynamically for those versions
    export TNS_ADMIN=$($ORACLE_HOME/bin/orabasehome)/network/admin
	export ORACLE_BASE_HOME=$($ORACLE_HOME/bin/orabasehome)
	export PASSWORD_FILE_FOLDER=$($ORACLE_HOME/bin/orabaseconfig)/dbs
else
        # For versions below 18c, those commands do not exist and typical folders are used
        export TNS_ADMIN=$ORACLE_HOME/network/admin
	export ORACLE_BASE_HOME=$ORACLE_HOME
	export PASSWORD_FILE_FOLDER=$ORACLE_HOME/dbs
fi

export A_DB_DOMAIN=$(echo $A_SERVICE |awk -F $A_DBNM. '{print $2}')
export B_DB_DOMAIN=$(echo $B_SERVICE |awk -F $B_DBNM. '{print $2}')

export SPFILE_ASM_LOC=$B_FILE_DEST/$B_DBNM/PARAMETERFILE
export PWFILE_ASM_LOC=$B_FILE_DEST/$B_DBNM/PASSWORD

#######################################################################
# Functions
########################################################################

check_rac_node(){
        if  [[ $RAC = "YES" ]]; then
                echo ""
                echo "This is a RAC"
                echo "Is this the first node of the standby RAC? [y/n]:"
                read -r -s  FIRST_NODE
                if  [[ $FIRST_NODE = "y" ]]; then
                        echo "This is the first node of the standby RAC"
                        echo ""
                elif [[ $FIRST_NODE = "n" ]]; then
                        echo "This is the second node of the standby RAC"
                        echo ""
                else
                        echo "Error: invalid value provided. Please answer y/n"
                        exit 1
                fi
        fi
}


show_databases_info(){
        if  [[ $RAC = "NO" ]]; then
                show_databases_info_single
        elif [[ $RAC = "YES" ]]; then
                show_databases_info_rac
        else
                echo "Error: provide a valid value for RAC input property. It must be set to YES or NO"
                exit 1
        fi
}

show_databases_info_single(){

	echo ""
	echo "DB Name is............................." $DB_NAME

	echo ""
	echo "**************************PRIMARY SYTEM INFORMATION GATHERED***************************"
        echo "Primary DB UNIQUE NAME................." $A_DBNM
        echo "Primary DB Port is....................." $A_PORT
        echo "Primary DB Host is....................." $A_DB_IP
	echo "Primary DB service name ..............." $A_SERVICE
        echo "****************************************************************************************"
        if [ -z "$A_DBNM" ] || [ -z "$DB_NAME" ] || [ -z "$A_PORT" ] || [ -z "$A_DB_IP" ] || [ -z "$A_SERVICE" ]; then
                echo "Error: one of the values  is null"
		exit 1
        fi

	echo ""
        echo "**************************SECONDARY SYTEM INFORMATION GATHERED***************************"
        echo "Secondary DB UNIQUE NAME................." $B_DBNM
        echo "Secondary DB Port is....................." $B_PORT
        echo "Secondary DB Host is....................." $B_DB_IP
        echo "Secondary DB service name ..............." $B_SERVICE
        echo "****************************************************************************************"
        if [ -z "$B_DBNM" ] || [ -z "$DB_NAME" ] || [ -z "$B_PORT" ] || [ -z "$B_DB_IP" ] || [ -z "$B_SERVICE" ] ; then
                echo "Error: one of the values  is null"
                exit 1
        fi


	echo ""
	echo "*************************OTHER VARIABLES*************************************************"
	echo "Secondary Oracle Home................." $ORACLE_HOME
	echo "Secondary Grid home..................." $GRID_HOME
	echo "Secondary tns admin folder............" $TNS_ADMIN
	echo "Location for TDE wallet folder........" $TDE_LOC_BASE
}

show_databases_info_rac(){
    echo ""
	echo "DB NAME is ............................" $DB_NAME

	echo ""
	echo "**************************PRIMARY SYTEM INFORMATION GATHERED****************************************"
    echo "Primary DB UNIQUE NAME................." $A_DBNM
	echo "Primary DB instance names are.........." ${A_SID1}, ${A_SID2}
    echo "Primary DB Port is....................." $A_PORT
    echo "Primary DB Service is.................." $A_SERVICE
    echo "Primary scan IPs are .................." $A_SCAN_IP1, $A_SCAN_IP2, $A_SCAN_IP3
    echo "Primary scan address is ..............." $A_SCAN_ADDRESS
        if [ -z "$A_DBNM" ] || [ -z "$DB_NAME" ] || [ -z "$A_PORT" ] || [ -z "$A_SCAN_IP1" ] || [ -z "$A_SCAN_ADDRESS" ] ; then
                echo "Error: one of the values  is null"
                exit 1
        fi

    echo ""
    echo "**************************SECONDARY SYTEM INFORMATION GATHERED**************************************"
    echo "Secondary DB UNIQUE NAME................." $B_DBNM
	echo "Secondary DB instance names are.........." ${B_SID1}, ${B_SID2}
    echo "Secondary DB Port is....................." $B_PORT
    echo "Secondary DB service name ..............." $B_SERVICE
    echo "Secondary DB scan IPs are ..............." $B_SCAN_IP1, $B_SCAN_IP2, $B_SCAN_IP3
    echo "Secondary DB scan address is ............" $B_SCAN_ADDRESS
        if [ -z "$B_DBNM" ] || [ -z "$DB_NAME" ] || [ -z "$B_PORT" ] || [ -z "$B_SCAN_IP1" ] || [ -z "$B_SCAN_ADDRESS" ] ; then
                echo "Error: one of the values  is null"
                exit 1
        fi

    echo ""
    echo "**************************OTHER VARIABLES***********************************************************"
    echo "Secondary Oracle Home................." $ORACLE_HOME
	echo "Secondary Grid home..................." $GRID_HOME
    echo "Secondary tns admin folder............" $TNS_ADMIN
    echo "Location for TDE wallet folder........" $TDE_LOC_BASE
    echo "***************************************************************************************************"
    echo ""

}



retrieve_sys_password(){
	if  [[ $RAC = "NO" ]]; then
            PRIMARY_CONNECT_ADDRESS=$A_DB_IP:$A_PORT/$A_SERVICE
    elif [[ $RAC = "YES" ]]; then
            PRIMARY_CONNECT_ADDRESS=$A_SCAN_IP1:$A_PORT/$A_SERVICE
    else
            echo "Error: provide a valid value for RAC input property. It must be set to YES or NO"
            exit 1
    fi

	export count=0;
	export top=3;
	while [ $count -lt  $top ]; do
		echo ""
		echo "Verifying connection to primary database...."
		echo "Enter the database SYS password: "
		read -r -s  SYS_USER_PASSWORD
		export db_type=$(
		echo "set feed off
		set pages 0
		select database_role from v\$database;
		exit
		"  | su $ORACLE_OSUSER -c "sqlplus -s $SYS_USERNAME/$SYS_USER_PASSWORD@$PRIMARY_CONNECT_ADDRESS as sysdba"
		)
		if  [[ $db_type = *PRIMARY* ]]; then
        		echo "Sys password is valid. Proceeding..."
        		count=3
		else
			echo "Invalid password or incorrect DB status";
			echo "Check that you can connect to the primary DB and that it is in Data Guard PRIMARY role."
			count=$(($count+1));
			if [ $count -eq 3 ]; then
        			echo "Error: Maximum number of attempts exceeded. Check DB connection and credentials"
	        		exit 1
			fi
		fi
	done
	
}


add_net_encryption(){
        #Add only if "SQLNET.ENCRYPTION_CLIENT=REQUIRED" or "SQLNET.ENCRYPTION_CLIENT=requested" are not already
        linecount1=$(grep -i "SQLNET.ENCRYPTION_CLIENT" $TNS_ADMIN/sqlnet.ora | grep -ci required )
        linecount2=$(grep -i "SQLNET.ENCRYPTION_CLIENT" $TNS_ADMIN/sqlnet.ora | grep -ci requested )
        if [[ $linecount1 -eq 0 && $linecount2 -eq 0 ]]; then
                echo ""
                echo "Adding SQLNET encryption parameters to $TNS_ADMIN/sqlnet.ora ..."
                su $ORACLE_OSUSER -c 'cp $TNS_ADMIN/sqlnet.ora $TNS_ADMIN/sqlnet.ora.${dt}'
		su $ORACLE_OSUSER -c 'cat >> $TNS_ADMIN/sqlnet.ora <<EOF
SQLNET.ENCRYPTION_CLIENT = requested
SQLNET.ENCRYPTION_TYPES_CLIENT = (AES256, AES192, AES128)
EOF
'
        echo "SQLNET encryption parameters added!"
        else
                echo ""
                echo "SQLNET encryption parameters already set in $TNS_ADMIN/sqlnet.ora "
        fi
}



check_connectivity(){
	# VERIFY CONNECTIVITY BETWEEN PRIMARY AND STANDBY
	export tnsping_primresult=$(
	su $ORACLE_OSUSER -c "tnsping ${A_DBNM}"
	)
	export tnsping_secresult=$(
	su $ORACLE_OSUSER -c "tnsping ${B_DBNM}"
	)
	#echo "TNSPING RESULT:" $tnsping_secresult
	if [[ $tnsping_primresult = *OK* ]]; then
	        echo "Remote primary database listener reachable on alias"
	else
        	echo "Error: Remote primary database cannot be reached using TNS alias. Either connectivty issues or errors in tnsnames"
		echo "Check that the listener is up in primary and that you have the correct config in tnsames"
	fi

	if [[ $tnsping_secresult = *OK* ]]; then
		echo "Standby database listener reachable on alias"
	else
        	echo "Error: Standby  database cannot be reached using TNS alias. Either connectivty issues or errors in tnsnames"
		echo "Check that the listener is up in standby and that you have the correct config in tnsames"
	fi

	if [[ $tnsping_primresult = *OK* ]] && [[ $tnsping_secresult = *OK* ]]; then
		echo "All good for tns connections!"
	else
		echo "ERROR: Could not establish the required connections to primary or standby. Can't proceed!"
		echo "Is this is an OCI environment check that VCNs and subnet rules are correct, also verify your iptables"
		echo "Dataguard across regions require Remote Peering in OCI"
		exit 1
	fi

}

delete_orig_db(){
	echo ""
	echo "Deleting previous standby DB (if it exists)..."
	if  [[ $RAC = "YES" ]]; then
		# For RAC cases unique name must be used
		DB_todelete=${B_DBNM}
	elif [[ $RAC = "NO" ]]; then
		DB_todelete=${DB_NAME}
	else
	        echo "ERROR: set variable RAC to "YES" if this is a RAC or to "NO" if single instance"
        	exit 1
	fi
	su $ORACLE_OSUSER -c "$ORACLE_HOME/bin/dbca -silent -deleteDatabase -sourceDB ${DB_todelete} -sysDBAUserName $SYS_USERNAME -sysDBAPassword ${SYS_USER_PASSWORD}  -forceArchiveLogDeletion"	
	echo "Database deleted!"

}

archivelog_cleanup(){
    # This is to avoid problems after duplication (ref Doc ID 1509932.1)
    echo ""
    echo "Deleting existing archivelogs in standby RECO..."
        #su - ${GRID_OSUSER} -c "$GRID_HOME/bin/asmcmd rm -rf ${B_RECOVERY_FILE_DEST}/${B_DBNM}/ARCHIVELOG/"
        #su - ${GRID_OSUSER} -c "$GRID_HOME/bin/asmcmd rm -rf ${B_RECOVERY_FILE_DEST}/${B_DBNM}/FLASHBACK/"
        #su - ${GRID_OSUSER} -c "$GRID_HOME/bin/asmcmd rm -rf ${B_RECOVERY_FILE_DEST}/${B_DBNM}/AUTOBACKUP/"
        #su - ${GRID_OSUSER} -c "$GRID_HOME/bin/asmcmd rm -rf ${B_RECOVERY_FILE_DEST}/${B_DBNM}/BACKUPSET/"
    su - ${GRID_OSUSER} -c "$GRID_HOME/bin/asmcmd rm -rf ${B_RECOVERY_FILE_DEST}/${B_DBNM}/"
	echo "Deleting existing datafiles in standby DATA..."
    su - ${GRID_OSUSER} -c "$GRID_HOME/bin/asmcmd rm -rf ${B_FILE_DEST}/${B_DBNM}/"

    echo "existing files in ${B_RECOVERY_FILE_DEST}/${B_DBNM}/ deleted!"
    echo "existing files in ${B_FILE_DEST}/${B_DBNM}/ deleted!"

}


shutdown_db(){
	echo ""
	echo "Shutting down standby DB..."
	su $ORACLE_OSUSER -c "sqlplus -s / as sysdba <<EOF
shutdown abort
EOF
"
	su $ORACLE_OSUSER -c "$ORACLE_HOME/bin/srvctl stop database -db ${B_DBNM} -stopoption abort"
	echo "DB shut down completed!"

}

remove_database_from_crs(){
	echo ""
	echo "Removing database from CRS..."
	su $ORACLE_OSUSER -c "$ORACLE_HOME/bin/srvctl remove database -db ${B_DBNM} -noprompt"
	echo "Database removed!"
}

remove_dataguard_broker_config(){
	echo ""
	echo "Removing previous DGBroker configuration from primary..."
	su $ORACLE_OSUSER -c "$ORACLE_HOME/bin/dgmgrl -silent ${SYS_USERNAME}/${SYS_USER_PASSWORD}@${A_DBNM} <<EOF
remove configuration
exit
EOF
" 
	echo "DGBroker configuration removed!"
}

get_wallet_from_primary(){
	if [ -z "$TDE_LOC_BASE" ]; then
		echo ""
                echo "TDE_LOC_BASE not provided. This is expected only if TDE is not used."
                echo "If TDE is used , verify the input parameters"
        else
		echo ""
		echo "Extracting wallet from $INPUT_WALLET_TAR ..."
		if [ ! -f $INPUT_WALLET_TAR ] || [ -z "$INPUT_WALLET_TAR" ]; then
			echo "Error: Input wallet tar $INPUT_WALLET_TAR does not exist or not correctly provided"
			exit 1
		fi
		su $ORACLE_OSUSER -c "mv ${TDE_LOC_BASE}/$B_DBNM ${TDE_LOC_BASE}/$B_DBNM.$dt"
		su $ORACLE_OSUSER -c "mkdir ${TDE_LOC_BASE}/$B_DBNM"
		cd $TDE_LOC_BASE/$B_DBNM
		su $ORACLE_OSUSER -c "tar -xzf $INPUT_WALLET_TAR"
# this is not needed because we are now retrieving .sso also (more feasible for RAC cases if TDE is not in shared location)
#	su $ORACLE_OSUSER -c "sqlplus -s / as sysdba <<EOF
#ADMINISTER KEY MANAGEMENT CREATE AUTO_LOGIN KEYSTORE FROM KEYSTORE '$TDE_LOC_BASE/$B_DBNM' IDENTIFIED BY ${SYS_USER_PASSWORD};
#EOF
#"

		echo "Wallet created in ${TDE_LOC_BASE}/$B_DBNM !"
		linecount=$(grep -ci "ENCRYPTION_WALLET_LOCATION=(SOURCE=(METHOD=FILE)(METHOD_DATA=(DIRECTORY=$TDE_LOC_BASE/$B_DBNM)))" $TNS_ADMIN/sqlnet.ora)
        	if [[ $linecount -eq 0  ]]; then
			echo "Adding wallet to $TNS_ADMIN/sqlnet.ora"
	 		su $ORACLE_OSUSER -c "cp $TNS_ADMIN/sqlnet.ora $TNS_ADMIN/sqlnet.ora.${dt}"
			su $ORACLE_OSUSER -c "cat >> $TNS_ADMIN/sqlnet.ora <<EOF
ENCRYPTION_WALLET_LOCATION=(SOURCE=(METHOD=FILE)(METHOD_DATA=(DIRECTORY=$TDE_LOC_BASE/$B_DBNM)))
EOF
"
		fi
	fi

}

configure_tns_alias(){
        if  [[ $RAC = "NO" ]]; then
                configure_tns_alias_single
        elif [[ $RAC = "YES" ]]; then
                configure_tns_alias_rac
        else
                echo "Error: provide a valid value for RAC input property. It must be set to YES or NO"
                exit 1
        fi


}


configure_tns_alias_single(){
	echo ""
	echo "Configuring TNS alias..."
	su $ORACLE_OSUSER -c 'cp $TNS_ADMIN/tnsnames.ora $TNS_ADMIN/tnsnames.ora.${dt}'
	su $ORACLE_OSUSER -c 'cat >> $TNS_ADMIN/tnsnames.ora <<EOF
${A_DBNM} =
  (DESCRIPTION =
    (SDU=65535)
    (RECV_BUF_SIZE=10485760)
    (SEND_BUF_SIZE=10485760)
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${A_DB_IP})(PORT = ${A_PORT}))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${A_SERVICE})
    )
  )
${B_DBNM} =
  (DESCRIPTION =
    (SDU=65535)
    (RECV_BUF_SIZE=10485760)
    (SEND_BUF_SIZE=10485760)
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${B_DB_IP})(PORT = ${B_PORT}))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${B_SERVICE})
    )
  )
EOF
'
	echo "TNS alias configured in $TNS_ADMIN/tnsnames.ora !"
	echo ""

}


configure_tns_alias_rac(){
        echo ""
        echo "Configuring TNS alias in $TNS_ADMIN/tnsnames.ora ..."
        su $ORACLE_OSUSER -c 'cp $TNS_ADMIN/tnsnames.ora $TNS_ADMIN/tnsnames.ora.${dt}'
        su $ORACLE_OSUSER -c 'cat >> $TNS_ADMIN/tnsnames.ora <<EOF
${A_DBNM} =
  (DESCRIPTION =
    (SDU=65535)
    (RECV_BUF_SIZE=10485760)
    (SEND_BUF_SIZE=10485760)
    (ADDRESS_LIST=
    (LOAD_BALANCE=on)
    (FAILOVER=on)
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${A_SCAN_IP1})(PORT = 1521))
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${A_SCAN_IP2})(PORT = 1521))
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${A_SCAN_IP3})(PORT = 1521)))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${A_SERVICE})
    )
  )
${B_DBNM} =
 (DESCRIPTION =
    (SDU=65535)
    (RECV_BUF_SIZE=10485760)
    (SEND_BUF_SIZE=10485760)
    (ADDRESS_LIST=
    (LOAD_BALANCE=on)
    (FAILOVER=on)
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${B_SCAN_IP1})(PORT = 1521))
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${B_SCAN_IP2})(PORT = 1521))
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${B_SCAN_IP3})(PORT = 1521)))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${B_SERVICE})
    )
   )

EOF
'
        echo "TNS alias configured in $TNS_ADMIN/tnsnames.ora !"
	echo ""
}



get_password_file(){
	echo ""
	echo "Extracting primary password file from $INPUT_PASWORD_TAR ...."
	if  [[ $RAC = "YES" ]]; then
                export PW_FILE_NAME=${PASSWORD_FILE_FOLDER}/orapw${B_SID1}
        else
                export PW_FILE_NAME=${PASSWORD_FILE_FOLDER}/orapw${DB_NAME}
        fi

        if [ ! -d "${PASSWORD_FILE_FOLDER}" ]; then
		echo "Error: the folder $PASSWORD_FILE_FOLDER does not exist"
		exit 1
	fi

	if [ ! -f $INPUT_PASWORD_TAR ] || [ -z "$INPUT_PASWORD_TAR" ]; then
		echo "Error: Input password file tar $INPUT_PASWORD_TAR does not exist or not correctly provided"
                exit 1
 	fi
	
	#This does not work, we need to copy it from primary
        #su $ORACLE_OSUSER -c "$ORACLE_HOME/bin/orapwd file=${PASSWORD_FILE_FOLDER}/orapw${DB_NAME} password=${SYS_USER_PASSWORD} force=y"
	su $ORACLE_OSUSER -c "cp ${PW_FILE_NAME} ${PW_FILE_NAME}.${dt}"
        su $ORACLE_OSUSER -c "tar -xzf $INPUT_PASWORD_TAR -C ${PASSWORD_FILE_FOLDER}/"
	
	if  [[ $RAC = "YES" ]]; then
		su $ORACLE_OSUSER -c "mv ${PASSWORD_FILE_FOLDER}/orapw${DB_NAME} ${PASSWORD_FILE_FOLDER}/orapw${B_SID1}"
	fi
	
	if [ -f "${PW_FILE_NAME}" ]; then
		echo "New password file ${PW_FILE_NAME} created!"
	else
		echo "Error: error extracting password file"
                exit 1
	fi

}

create_standby_dirs(){
	echo ""
	echo "Creating standby DIR structure..."
	su $ORACLE_OSUSER -c "mkdir -p $ORACLE_BASE/admin/${B_DBNM}/adump"
	su $ORACLE_OSUSER -c "mkdir -p $ORACLE_BASE/admin/${B_DBNM}/dpump"
	su $ORACLE_OSUSER -c "mkdir -p $ORACLE_BASE/admin/${B_DBNM}/xdb_wallet"
	su $ORACLE_OSUSER -c "mkdir -p $ORACLE_BASE/admin/${B_DBNM}/pfile"
	su $ORACLE_OSUSER -c "mkdir -p $ORACLE_BASE/admin/${B_DBNM}/db_wallet"
	su $ORACLE_OSUSER -c "mkdir -p $ORACLE_BASE/admin/${B_DBNM}/tde_wallet"
	chown -R ${ORACLE_OSUSER}:${ORACLE_OSGROUP} "$ORACLE_BASE/admin/${B_DBNM}/adump"
	chown -R ${ORACLE_OSUSER}:${ORACLE_OSGROUP} "$ORACLE_BASE/admin/${B_DBNM}/dpump"
	chown -R ${ORACLE_OSUSER}:${ORACLE_OSGROUP} "$ORACLE_BASE/admin/${B_DBNM}/db_wallet"
	chown -R ${ORACLE_OSUSER}:${ORACLE_OSGROUP} "$ORACLE_BASE/admin/${B_DBNM}/pfile"
	echo "Standby directories created!"
}

start_auxiliary_db(){
	echo ""
        echo "Starting Auxiliary DB..."
	if  [[ $RAC = "YES" ]]; then
        	export ORACLE_SID=${B_SID1}
	else
		export ORACLE_SID=${DB_NAME}
	fi
        cat > /tmp/aux.pfile << EOF
db_name=${DB_NAME}
db_unique_name=${B_DBNM}
sga_target=800M
EOF
        chmod o+rw /tmp/aux.pfile
        su $ORACLE_OSUSER -c "$ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
startup nomount pfile='/tmp/aux.pfile'
EOF
" 
}

restore_spfile_from_service(){
	echo ""
	echo "Restoring spfile from primary service ...."
	if  [[ $RAC = "YES" ]]; then
        	cat >/tmp/restore_spfile.rman <<EOF
run {
restore spfile to '/tmp/retrieved_spfile.ora' from service '${A_DBNM}';
create pfile='/tmp/retrieved.pfile' from spfile='/tmp/retrieved_spfile.ora';
}
EOF
	else
		cat >/tmp/restore_spfile.rman <<EOF
run {
restore spfile from service '${A_DBNM}' ;
create pfile='/tmp/retrieved.pfile' from spfile;
}
EOF
	fi
	chown ${ORACLE_OSUSER}:${ORACLE_OSGROUP} /tmp/restore_spfile.rman
	su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/rman target ${SYS_USERNAME}/${SYS_USER_PASSWORD} <<EOF
@/tmp/restore_spfile.rman
EOF
"
	if [ ! -f /tmp/retrieved.pfile ]; then
		echo "Error: pfile not found. Error retrieving the spfile from primary"
		exit 1
	else
		echo "spfile retrieved from primary!"
	fi
}

modify_retrieved_pfile(){
	echo ""
	echo "Preparing the retrieved pfile for standby database..."
	cp /tmp/retrieved.pfile /tmp/retrieved.pfile_PRIMARY

	# Modifications for the DB unique name
	########################################
	if  [[ $RAC = "NO" ]]; then
		sed -i "s/${A_DBNM}/${B_DBNM}/g" /tmp/retrieved.pfile
	fi
	# Previous replacement is a problem in RAC when 
	# - A_DBNM is contained in A_SID1 and A_SID2 
	# - and B_SID1 and B_SID2 are not derived from B_DBNM
	# because it will replace B_SID1 and B_SID2 to B_DBNM1xxx and B_DBNM2xxx, not matching expectation
	# (The problem only found in heterogeneous systems like hybrid DG)
	# So exluding patterns in RAC cases
	if  [[ $RAC = "YES" ]]; then
		sed -i "/\(${A_SID1}\|${A_SID2}\)/! s/${A_DBNM}/${B_DBNM}/g" /tmp/retrieved.pfile
	fi

	# When DB_NAME is the same than A_DBNM in primary previous replacement can modify it, so explicitely setting DB_NAME 
	sed -i '/db_name/d' /tmp/retrieved.pfile
	echo "*.db_name='${DB_NAME}'" >> /tmp/retrieved.pfile

	# For cases when the primary db does not have the db_unique_name defined
	sed -i '/*.db_unique_name/d' /tmp/retrieved.pfile
        echo "*.db_unique_name='${B_DBNM}'" >> /tmp/retrieved.pfile

	# Modifications for the DB domain name
	######################################
	if [[ ! -z ${A_DB_DOMAIN} && ! -z ${B_DB_DOMAIN} ]]; then
		# if domain values are not null
		sed -i "s/${A_DB_DOMAIN}/${B_DB_DOMAIN}/g" /tmp/retrieved.pfile
	elif [[ -z ${A_DB_DOMAIN} && ! -z ${B_DB_DOMAIN} ]]; then
		# if primary db domain is null and standby db domain not null
		sed -i '/db_domain=/d' /tmp/retrieved.pfile
		echo "*.db_domain='${B_DB_DOMAIN}'" >> /tmp/retrieved.pfile
	elif [[ ! -z ${A_DB_DOMAIN} && -z ${B_DB_DOMAIN} ]]; then
		#if primary db domain is not null and standby db domain is null 
		sed -i '/db_domain=/d' /tmp/retrieved.pfile	
	else
		# nothing to do if both are null
		echo "db_domain not defined for primary nor standby DB"
	fi

	# Modifications for the default dest locations
	#############################################
	sed -i "s/${A_FILE_DEST}/${B_FILE_DEST}/g" /tmp/retrieved.pfile
	sed -i "s/${A_ONLINE_LOG_DEST1}/${B_ONLINE_LOG_DEST1}/g" /tmp/retrieved.pfile
	sed -i "s/${A_RECOVERY_FILE_DEST}/${B_RECOVERY_FILE_DEST}/g" /tmp/retrieved.pfile
	# For corner cases where db_create_file_dest is replaced with other value
	sed -i '/db_create_file_dest/d' /tmp/retrieved.pfile
	echo "*.db_create_file_dest='${B_FILE_DEST}'" >> /tmp/retrieved.pfile


	# Other clean ups
	#################
	sed -i '/log_file_name_convert/d' /tmp/retrieved.pfile
	sed -i '/db_file_name_convert/d' /tmp/retrieved.pfile

	# RAC specific modifications
	#############################
	if  [[ $RAC = "YES" ]]; then
		sed -i "s/${A_SID1}/${B_SID1}/g" /tmp/retrieved.pfile
		sed -i "s/${A_SID2}/${B_SID2}/g" /tmp/retrieved.pfile

		export B_LOCAL_LISTENER1="(ADDRESS=(PROTOCOL=tcp)(HOST=${B_VIP1})(PORT=${B_PORT}))"
		export B_LOCAL_LISTENER2="(ADDRESS=(PROTOCOL=tcp)(HOST=${B_VIP2})(PORT=${B_PORT}))"
		sed -i '/local_listener/d' /tmp/retrieved.pfile
		echo "${B_SID1}.local_listener='${B_LOCAL_LISTENER1}'" >> /tmp/retrieved.pfile
		echo "${B_SID2}.local_listener='${B_LOCAL_LISTENER2}'" >> /tmp/retrieved.pfile

		sed -i '/remote_listener/d' /tmp/retrieved.pfile
		echo "*.remote_listener='${B_SCAN_ADDRESS}:${B_PORT}'" >> /tmp/retrieved.pfile
		
		# Reset the cluster interconnects primary's info	
		sed -i '/cluster_interconnects/d' /tmp/retrieved.pfile
		# Configure cluster interconnects only if RAC and if values are provided
		if [ ! -z ${B_INTERCONNECT_IP1} ]; then 
			echo "${B_SID1}.cluster_interconnects='${B_INTERCONNECT_IP1}'" >> /tmp/retrieved.pfile
			echo "${B_SID2}.cluster_interconnects='${B_INTERCONNECT_IP2}'" >> /tmp/retrieved.pfile
		fi
	fi

	echo ""	
	echo "Starting db with this pfile ..."
	su $ORACLE_OSUSER -c "$ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
shutdown abort
startup nomount pfile='/tmp/retrieved.pfile'
EOF
" 
}

cp_spfile_asm() {
	echo ""
        echo "Creating spfile in ASM..."
        su - ${GRID_OSUSER} -c "$GRID_HOME/bin/asmcmd mkdir ${SPFILE_ASM_LOC}"
        echo "Ignore failures if folder already exists"
        su $ORACLE_OSUSER -c "sqlplus -s / as sysdba <<EOF
create spfile='${SPFILE_ASM_LOC}/spfile${B_DBNM}.ora' from pfile='/tmp/retrieved.pfile';
exit;
EOF
"
        echo "Created spfile in ASM in  ${SPFILE_ASM_LOC}/spfile${B_DBNM}.ora"

	if  [[ $RAC = "YES" ]]; then
		DEFAULT_INIT_NAME=init${B_SID1}.ora
		DEFAULT_SPFILE_NAME=spfile${B_SID1}.ora
	elif [[ $RAC = "NO" ]]; then
		DEFAULT_INIT_NAME=init${DB_NAME}.ora
		DEFAULT_SPFILE_NAME=spfile${DB_NAME}.ora
	else
                echo "Error: provide a valid value for RAC input property. It must be set to YES or NO"
                exit 1
        fi
	# Remove spfile from $ORACLE_HOME/dbs, to prevent mistakes. Only the spfile in ASM will be used
	# and creating default pfile pointing to the spfile in asm
	rm -f $ORACLE_BASE_HOME/dbs/${DEFAULT_SPFILE_NAME}
        su ${ORACLE_OSUSER} -c "cat > $ORACLE_BASE_HOME/dbs/${DEFAULT_INIT_NAME} <<EOF
spfile='${SPFILE_ASM_LOC}/spfile${B_DBNM}.ora'
EOF
"
	echo "Created default pfile $ORACLE_BASE_HOME/dbs/${DEFAULT_INIT_NAME} pointing to the spfile in ASM"
}

add_database_to_crs(){
        if  [[ $RAC = "NO" ]]; then
                add_database_to_crs_single
        elif [[ $RAC = "YES" ]]; then
                add_database_to_crs_rac
        else
                echo "Error: provide a valid value for RAC input property. It must be set to YES or NO"
                exit 1
        fi
}


add_database_to_crs_single(){
	export STBY_HOSTNAME=$(su - ${GRID_OSUSER} -c "${GRID_HOME}/bin/olsnodes | sed -n 1p")
	echo ""
        echo "Adding standby DB to CRS..."
        su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl add database -db ${B_DBNM} -oraclehome $ORACLE_HOME -dbtype SINGLE -node $STBY_HOSTNAME -instance ${DB_NAME} -dbname ${DB_NAME}"
        su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl modify database -db ${B_DBNM} -role physical_standby -spfile ${SPFILE_ASM_LOC}/spfile${B_DBNM}.ora"
        if  [[ $PASSWORD_FILE_IN_ASM = "YES" ]]; then
                cp_pwfile_asm
                su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl modify database -db ${B_DBNM} -pwfile ${PWFILE_ASM_LOC}/orapw${DB_NAME}"
        else
                su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl modify database -db ${B_DBNM} -pwfile ${PASSWORD_FILE_FOLDER}/orapw${DB_NAME}"
        fi
        su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl setenv database -db ${B_DBNM} -T \"ORACLE_UNQNAME=${B_DBNM}\" "
        su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl setenv database -db ${B_DBNM} -T \"TZ=UTC\""
	echo ""
        echo "Standby DB added to CRS!"
	echo ""
	echo "$ORACLE_HOME/bin/srvctl config database -db ${B_DBNM}"
        su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl config database -db ${B_DBNM}"
	echo ""
        su ${ORACLE_OSUSER} -c "cat >> /etc/oratab <<EOF
${DB_NAME}:${ORACLE_HOME}:N
EOF
"

}

add_database_to_crs_rac(){
	echo ""
        echo "Adding standby DB to CRS..."
	#first need to put the password file in ASM
	cp_pwfile_asm

        export RACNODE1=$(su - ${GRID_OSUSER} -c "${GRID_HOME}/bin/olsnodes | sed -n 1p")
        export RACNODE2=$(su - ${GRID_OSUSER} -c "${GRID_HOME}/bin/olsnodes | sed -n 2p")

        su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl add database -db ${B_DBNM} -oraclehome $ORACLE_HOME -dbname ${DB_NAME}"
        su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl add instance -db ${B_DBNM} -instance ${B_SID1} -node $RACNODE1"
        su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl add instance -db ${B_DBNM} -instance ${B_SID2} -node $RACNODE2"
        su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl modify database -db ${B_DBNM} -role physical_standby -spfile ${SPFILE_ASM_LOC}/spfile${B_DBNM}.ora -pwfile ${PWFILE_ASM_LOC}/orapw${DB_NAME}"
        su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl setenv database -d ${B_DBNM} -T \"ORACLE_UNQNAME=${B_DBNM}\" "
        su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl setenv database -d ${B_DBNM} -T "TZ=UTC" "
	echo ""
        echo "Standby DB added to CRS!"
	echo ""
	echo "$ORACLE_HOME/bin/srvctl config database -db ${B_DBNM}"
	su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl config database -db ${B_DBNM}"
	echo ""
}




restore_database_from_service(){
	echo ""
	echo "Creating standby database using restoring from service rman command.."
	echo "check output log file in /tmp/dataguardit.$dt.log"
	# rman configure commands are because the rman config from primary is applied given that the primary crontrol file is retrieved
	# see 32040735
	cat >/tmp/restore_db_from_service.rman <<EOF
run {
startup nomount
restore standby controlfile from service '${A_DBNM}';
alter database mount;
CONFIGURE DEVICE TYPE 'SBT_TAPE' clear;
CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' clear;
restore database from service '${A_DBNM}' section size 5G;
}
switch database to copy;
EOF

        chown ${ORACLE_OSUSER}:${ORACLE_OSGROUP} /tmp/restore_db_from_service.rman
        su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/rman target ${SYS_USERNAME}/${SYS_USER_PASSWORD} << EOF
@/tmp/restore_db_from_service.rman
EOF
" >> /tmp/dataguardit.$dt.log
	echo "------------------------------------------------------------------------------------------------------------" >> /tmp/dataguardit.$dt.log
	echo "NOTE:" >> /tmp/dataguardit.$dt.log
	echo "The command \"switch database to copy;\" is not always necessary so may result in a no-op (nothing executes)" >> /tmp/dataguardit.$dt.log
	echo "Ignore the message \"RMAN-03002: failure of switch to copy.." >> /tmp/dataguardit.$dt.log
	echo "------------------------------------------------------------------------------------------------------------" >> /tmp/dataguardit.$dt.log
}

clear_logs(){
        echo ""
        echo "Clearing the logfiles. This can take some time..."

	cat > /tmp/clear_logs.sql <<EOF
begin
for log_cur in ( select group# group_no from v\$log )
loop
execute immediate 'alter database clear logfile group '||log_cur.group_no;
end loop;
end;
/

begin
for log_cur in ( select group# group_no from v\$standby_log )
loop
execute immediate 'alter database clear logfile group '||log_cur.group_no;
end loop;
end;
/
EOF

	chown ${ORACLE_OSUSER}:${ORACLE_OSGROUP} /tmp/clear_logs.sql
	su $ORACLE_OSUSER -c "$ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
@/tmp/clear_logs.sql
EOF
"

}


cp_pwfile_asm() {
	echo ""
	echo "Copying password file to ASM..."
	su - ${GRID_OSUSER} -c "${GRID_HOME}/bin/asmcmd mkdir ${PWFILE_ASM_LOC}"
	echo "Ignore failures if folder already exists"

	#this creates DB_UNKNOWN regardless (Doc ID 2329386.1) (Doc ID 1984091.1)
	su - ${GRID_OSUSER} -c "${GRID_HOME}/bin/asmcmd pwcopy ${PW_FILE_NAME} ${PWFILE_ASM_LOC}/orapw${DB_NAME} "
	# this fails to create the file and it seems expected as per 1984091.1
        #su - ${GRID_OSUSER} -c "${GRID_HOME}/bin/asmcmd pwcopy --dbuniquename ${B_DBNM} $PASSWORD_FILE_FOLDER/orapw${DB_NAME} ${PWFILE_ASM_LOC}/orapw${DB_NAME} -f "
	#this creates it in the right place, but  does not work, pw file needs to be a copy of the primary file and this creates a new one:
	#su $ORACLE_OSUSER -c "$ORACLE_HOME/bin/orapwd file=${PWFILE_ASM_LOC}/orapw${DB_NAME} password=${SYS_USER_PASSWORD} dbuniquename=${B_DBNM} force=y"i
	
	#cleaning default pw file from filesystem
	rm -f ${PW_FILE_NAME} 
	echo "Copied password file to ASM   ${PWFILE_ASM_LOC}/orapw${DB_NAME}  !"
}



start_database_mount() {
	echo ""
	if  [[ $RAC = "NO" ]]; then
		echo "Starting database in mount with srvctl..."
		su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl start database -d ${B_DBNM} -startoption mount"
        elif [[ $RAC = "YES" ]]; then
		echo "Starting database instance in mount with srvctl..."
		su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl start instance -db ${B_DBNM} -instance ${B_SID1}  -startoption mount"
        else
                echo "Error: provide a valid value for RAC input property. It must be set to YES or NO"
                exit 1
        fi

}

start_database_mount_second_instance_only() {
	echo ""
	echo "Starting database instance in mount with srvctl..."
	su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl start instance -db ${B_DBNM} -instance ${B_SID2}  -startoption mount"
}


start_database_nomount() {
	echo ""
        if  [[ $RAC = "NO" ]]; then
                echo "Starting database in nomount with srvctl..."
                su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl start database -d ${B_DBNM} -startoption nomount"
        elif [[ $RAC = "YES" ]]; then
		echo "Starting database instance in nomount with srvctl..."
                su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/srvctl start instance -db ${B_DBNM} -instance ${B_SID1}  -startoption nomount"
        else
                echo "Error: provide a valid value for RAC input property. It must be set to YES or NO"
                exit 1
        fi
}

restart_database_mount(){
	shutdown_db
	start_database_mount
}



create_dataguard_broker_config(){
	echo ""
	echo "Creating new DG Broker configuration..."
	su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/sqlplus -s ${SYS_USERNAME}/${SYS_USER_PASSWORD}@${A_DBNM} as sysdba <<EOF
  alter system set dg_broker_start=FALSE;
  alter system set dg_broker_config_file1='${A_FILE_DEST}/dr1.dat';
  alter system set dg_broker_config_file2='${A_RECOVERY_FILE_DEST}/dr2.dat';
  alter system set dg_broker_start=TRUE;
  exit;
EOF
"
	su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
alter system set dg_broker_start=FALSE;
alter system set dg_broker_config_file1='${B_FILE_DEST}/dr1.dat';
alter system set dg_broker_config_file2='${B_RECOVERY_FILE_DEST}/dr2.dat';
alter system set dg_broker_start=TRUE;
exit;
EOF
"
	sleep 20

	su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/dgmgrl -silent ${SYS_USERNAME}/${SYS_USER_PASSWORD}@${A_DBNM} <<EOF
create configuration '${A_DBNM}_${B_DBNM}' as primary database is '${A_DBNM}'  connect identifier is '${A_DBNM}';
add database '${B_DBNM}' as connect identifier is '${B_DBNM}';
EDIT CONFIGURATION SET PROTECTION MODE AS MaxPerformance;
enable configuration;
show configuration verbose
exit
EOF
"
	sleep 20
	echo "New DG Broker configuration created!"
}


enable_flashback_standby(){
	echo ""
        echo "Enabling flashback in standby..."
        su ${ORACLE_OSUSER} -c "$ORACLE_HOME/bin/dgmgrl -silent ${SYS_USERNAME}/${SYS_USER_PASSWORD}@${B_DBNM} <<EOF
EDIT DATABASE '${B_DBNM}' SET STATE=APPLY-OFF;
SQL \"ALTER DATABASE FLASHBACK ON\";
EDIT DATABASE '${B_DBNM}' SET STATE=APPLY-ON;
EOF
"
	echo ""
	echo "NOTE: Enabling flashback database in standby database may fail if the standby is still applying redo."
	echo "If that is the case, check the dataguard status using "show configuration" in dgmgrl"
	echo "and try to enable flashback in standby database again once it shows SUCCESS."
}




echo "#############################################################################################"
echo "############## This script will configure Data Guard ########################################"
echo "#############################################################################################"
touch /tmp/dataguardit.$dt.log
echo "Output log file in /tmp/dataguardit.$dt.log"
echo ""
check_rac_node
show_databases_info
echo ""

#If this is running in the second RAC node, only these are required
if  [[ $RAC = "YES" ]] && [[ $FIRST_NODE = "n" ]]; then
	echo "#######################################################################################"
	echo "#### The script is running in the second node of the standby RAC ######################"
	echo "#### Note: make sure you ALREADY run this script in the first node of the standby RAC #"
	echo "#######################################################################################"
        add_net_encryption
        configure_tns_alias
        check_connectivity
        create_standby_dirs
        get_wallet_from_primary  # if TDE is used and if it is not in a shared folder
        start_database_mount_second_instance_only
	echo "#############################################################################################"
	echo "################  ALL DONE! Check the resulting dgbroker config #############################"
	echo "#############################################################################################"
	exit
fi


echo "###################################################"
echo "#### Initial connectivity checks ##################"
echo "###################################################"
configure_tns_alias
check_connectivity
retrieve_sys_password
echo ""

echo "###################################################"
echo "#### Cleanup DG conf and removing secondary DB ####"
echo "###################################################"
remove_dataguard_broker_config
delete_orig_db
archivelog_cleanup
shutdown_db
remove_database_from_crs
echo ""

echo "###################################################"
echo "#### Recreating tns alias #########################"
echo "###################################################"
# When the db is deleted, the tns aliases are removed, so we need to add it again
add_net_encryption
configure_tns_alias
check_connectivity
echo ""

echo "###################################################"
echo "#### Preparing to create the standby database #####"
echo "###################################################"
create_standby_dirs
get_password_file
start_auxiliary_db
get_wallet_from_primary
restore_spfile_from_service
modify_retrieved_pfile
cp_spfile_asm
echo ""

echo "###################################################"
echo "#### Adding database to CRS and restarting    #####"
echo "###################################################"
# Add database to CRS and restart using these asm spfile and pw file
add_database_to_crs
shutdown_db
start_database_nomount
echo ""

echo "###################################################"
echo "#### Restoring database from service   ############"
echo "###################################################"
restore_database_from_service
clear_logs
restart_database_mount
echo ""

echo "#######################################################"
echo "#### Configuring DG broker and enabling flashback #####"
echo "#######################################################"
create_dataguard_broker_config
enable_flashback_standby
echo ""

echo "#############################################################################################"
echo "################  ALL DONE! Check the resulting dgbroker config #############################"
echo "#############################################################################################"

