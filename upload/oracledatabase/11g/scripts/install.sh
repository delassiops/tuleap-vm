#!/bin/bash
#
# LICENSE UPL 1.0
#
# Copyright (c) 1982-2018 Oracle and/or its affiliates. All rights reserved.
# 
# Since: July, 2018
# Author: gerald.venzl@oracle.com
# Description: Installs Oracle database software
# 
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

# MAINTAINER: Oussama DELASSI

# Abort on any error
set -e

echo 'ORACLE INSTALLER: Started up'

# fix locale warning
yum reinstall -y glibc-common
echo LANG=en_US.utf-8 >> /etc/environment
echo LC_ALL=en_US.utf-8 >> /etc/environment

echo 'ORACLE INSTALLER: Locale set'

# Install Oracle Database prereq and openssl, unzip packages
yum install -y oracle-rdbms-server-11gR2-preinstall openssl unzip

echo 'ORACLE INSTALLER: Oracle preinstall and openssl complete'


# create directories & change owner
ORACLE_INVENTORY="${ORACLE_BASE}/../oraInventory"
install --owner oracle --group oinstall --mode=775 --verbose --directory ${ORACLE_BASE} ${ORACLE_INVENTORY} ${ORACLE_HOME}
chown -vR oracle:oinstall ${ORACLE_BASE} ${ORACLE_INVENTORY} ${ORACLE_HOME}


echo 'ORACLE INSTALLER: Oracle directories created'

# set environment variables
echo "export ORACLE_BASE=$ORACLE_BASE" >> /home/oracle/.bashrc
echo "export ORACLE_HOME=$ORACLE_HOME" >> /home/oracle/.bashrc
echo "export ORACLE_SID=$ORACLE_SID" >> /home/oracle/.bashrc
echo "export PATH=\$PATH:\$ORACLE_HOME/bin" >> /home/oracle/.bashrc

echo 'ORACLE INSTALLER: Environment variables set'

# Install Oracle
echo "ORACLE INSTALLER: Extracting Oracle Database software. Please be patient..."
unzip -qq "/tmp/$OracleRelease/linux.x64_11gR2_database_?of2.zip" -d $ORACLE_HOME/
if [ -d "${ORACLE_HOME}/database" ]; then
            echo " - Legacy OUI software setup"
            mv ${ORACLE_HOME}/database ${ORACLE_HOME}/..
            SETUP_PATH="${ORACLE_HOME}/../database"
fi
echo "ORACLE INSTALLER: Extracting Oracle Database software. Completed Successfully."
cp -f /tmp/$OracleRelease/ora-response/db_install.rsp.tmpl /home/oracle/db_install.rsp
sed -i -e "s|###ORACLE_BASE###|$ORACLE_BASE|g" /home/oracle/db_install.rsp
sed -i -e "s|###ORACLE_HOME###|$ORACLE_HOME|g" /home/oracle/db_install.rsp
sed -i -e "s|###ORACLE_EDITION###|$ORACLE_EDITION|g" /home/oracle/db_install.rsp
sed -i -e "s|###ORACLE_INVENTORY###|$ORACLE_INVENTORY|g" /home/oracle/db_install.rsp

su -l oracle -c "yes | $SETUP_PATH/runInstaller -silent -waitforcompletion -responseFile /home/oracle/db_install.rsp -ignoreSysPrereqs -ignorePrereq"
$ORACLE_INVENTORY/orainstRoot.sh
$ORACLE_HOME/root.sh
rm -f /home/oracle/db_install.rsp
rm -rf "${ORACLE_HOME}/../database"

echo 'ORACLE INSTALLER: Oracle software installed'

# create sqlnet.ora parameters

su -l oracle -c "echo 'NAME.DIRECTORY_PATH= (TNSNAMES, EZCONNECT, HOSTNAME)' > $ORACLE_HOME/network/admin/sqlnet.ora"
su -l oracle -c "echo 'SQLNET.ALLOWED_LOGON_VERSION_SERVER=8' >> $ORACLE_HOME/network/admin/sqlnet.ora"
su -l oracle -c "echo 'SQLNET.ALLOWED_LOGON_VERSION_CLIENT=8' >> $ORACLE_HOME/network/admin/sqlnet.ora"

echo 'ORACLE INSTALLER: SQLNET.ORA Network Configuration File created'

# Listener.ora: Check Listener Registration (LREG)

# Tnsnames.ora

su -l oracle -c "echo '$ORACLE_SID= 
(DESCRIPTION = 
  (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
  (CONNECT_DATA =
    (SERVER = DEDICATED)
    (SERVICE_NAME = $ORACLE_SID)
  )
)' >> $ORACLE_HOME/network/admin/tnsnames.ora"

# Open 1521 listener port

sudo firewall-cmd --permanent --add-port=1521/tcp

sudo firewall-cmd --reload


# Create database

# Auto generate ORACLE PWD if not passed on
export ORACLE_PWD=${ORACLE_PWD:-"`openssl rand -base64 8`1"}

cp -f /tmp/$OracleRelease/ora-response/dbca.rsp.tmpl /home/oracle/dbca.rsp
sed -i -e "s|###ORACLE_SID###|$ORACLE_SID|g" /home/oracle/dbca.rsp
sed -i -e "s|###ORACLE_CHARACTERSET###|$ORACLE_CHARACTERSET|g" /home/oracle/dbca.rsp
sed -i -e "s|###ORACLE_PWD###|$ORACLE_PWD|g" /home/oracle/dbca.rsp
sed -i -e "s|###ORACLE_HOME###|$ORACLE_HOME|g" /home/oracle/dbca.rsp
sed -i -e "s|###ORACLE_BASE###|$ORACLE_BASE|g" /home/oracle/dbca.rsp

# Start dbca 
su -l oracle -c "dbca -silent -createDatabase -responseFile /home/oracle/dbca.rsp"

rm -f /home/oracle/dbca.rsp

echo 'ORACLE INSTALLER: Database created'

sed 's/:N/:Y/g' /etc/oratab | sudo tee /etc/oratab > /dev/null
echo 'ORACLE INSTALLER: Oratab configured'

# configure systemd to start oracle instance on startup
sudo cp -f /tmp/$OracleRelease/scripts/oracle-rdbms.service /etc/systemd/system/
sudo sed -i -e "s|###ORACLE_HOME###|$ORACLE_HOME|g" /etc/systemd/system/oracle-rdbms.service
sudo systemctl daemon-reload
sudo systemctl enable oracle-rdbms
sudo systemctl start oracle-rdbms
echo "ORACLE INSTALLER: Created and enabled oracle-rdbms systemd's service"

sudo cp -f /tmp/$OracleRelease/scripts/setPassword.sh /home/oracle/
sudo chmod a+rx /home/oracle/setPassword.sh


echo "ORACLE INSTALLER: setPassword.sh file setup";

# run user-defined post-setup scripts
echo 'ORACLE INSTALLER: Running user-defined post-setup scripts'

for f in /tmp/$OracleRelease/userscripts/*
  do
    case "${f,,}" in
      *.sh)
        echo "ORACLE INSTALLER: Running $f"
        . "$f"
        echo "ORACLE INSTALLER: Done running $f"
        ;;
      *.sql)
        echo "ORACLE INSTALLER: Running $f"
        su -l oracle -c "echo 'exit' | sqlplus -s / as sysdba @\"$f\""
        echo "ORACLE INSTALLER: Done running $f"
        ;;
      /tmp/$OracleRelease/userscripts/put_custom_scripts_here.txt)
        :
        ;;
      *)
        echo "ORACLE INSTALLER: Ignoring $f"
        ;;
    esac
  done

echo 'ORACLE INSTALLER: Done running user-defined post-setup scripts'

echo "ORACLE PASSWORD FOR SYS AND SYSTEM: $ORACLE_PWD";


echo "ORACLE INSTALLER: Installation complete, database ready to use!";
