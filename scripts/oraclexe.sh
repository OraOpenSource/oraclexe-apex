#!/bin/bash

#*** ORACLE ***
#Get Files needed to install
cd $OOS_SOURCE_DIR/tmp
${OOS_UTILS_DIR}/download.sh $OOS_ORACLE_FILE_URL

#Install Oracle
cd $OOS_SOURCE_DIR/tmp

OOS_ORACLE_PREINSTALL_FILENAME="$( sed 's/xe/preinstall/g' <<< ${OOS_ORACLE_FILENAME//.x86/.el7.x86})"
curl -o $OOS_ORACLE_PREINSTALL_FILENAME https://yum.oracle.com/repo/OracleLinux/OL7/latest/x86_64/getPackage/$OOS_ORACLE_PREINSTALL_FILENAME
echo OOS_ORACLE_PREINSTALL_FILENAME: $OOS_ORACLE_PREINSTALL_FILENAME

yum -y localinstall $OOS_ORACLE_PREINSTALL_FILENAME
yum -y localinstall $OOS_ORACLE_FILENAME
# silent configuration
perl -i -p -e "s/LISTENER_PORT=/LISTENER_PORT=$OOS_ORACLE_TNS_PORT/g" /etc/sysconfig/oracle-xe-18c.conf
echo "ORACLE_PASSWORD=$OOS_ORACLE_PWD" >> /etc/sysconfig/oracle-xe-18c.conf

#Update the .ora files to use localhost instead of the current hostname
#This is required since Amazon AMIs change the hostname
cd /opt/oracle/product/18c/dbhomeXE/network/admin
#backup files
mv listener.ora listener.bkp
mv tnsnames.ora tnsnames.bkp

#cp new files from OOS
cp $OOS_SOURCE_DIR/oracle/listener.ora .
cp $OOS_SOURCE_DIR/oracle/tnsnames.ora .

perl -i -p -e "s/1521/$OOS_ORACLE_TNS_PORT/g" listener.ora
perl -i -p -e "s/1521/$OOS_ORACLE_TNS_PORT/g" tnsnames.ora

cd $OOS_SOURCE_DIR

/etc/init.d/oracle-xe-18c configure

#Configure env variables
ORACLE_SID=XE
ORAENV_ASK=NO
. /opt/oracle/product/18c/dbhomeXE/bin/oraenv

# Start Oracle XE services at boot
systemctl daemon-reload
systemctl enable oracle-xe-18c

echo; echo \* DB install complete \*; echo

#Create a profile to set environment
cd ${OOS_SOURCE_DIR}/profile.d
#Use | as field seperator to get around issue with / being field separator
# See: http://askubuntu.com/questions/76785/how-to-escape-file-path-in-sed
# Alternate solution: http://stackoverflow.com/questions/407523/escape-a-string-for-a-sed-replace-pattern
sed -i "s|ORACLE_HOME|${ORACLE_HOME}|" 20oos_oraclexe.sh
cp 20oos_oraclexe.sh /etc/profile.d/


#restart oracle
/etc/init.d/oracle-xe-18c stop
/etc/init.d/oracle-xe-18c start


cd $OOS_SOURCE_DIR/oracle/
sqlplus -L system/${OOS_ORACLE_PWD}@localhost:${OOS_ORACLE_TNS_PORT}/xepdb1 @validate.sql > /dev/null
DB_VALIDATE_RESULT=$?
if [[ $DB_VALIDATE_RESULT -ne 0 ]]; then
    echo "The database installation seems to have failed. Exiting install" >&2
    echo "Please check logs for an indication of what went wrong" >&2
    exit $DB_VALIDATE_RESULT
fi

#Cleanup
cd $OOS_SOURCE_DIR/tmp
rm -rf $OOS_ORACLE_FILENAME
