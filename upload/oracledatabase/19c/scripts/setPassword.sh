#!/bin/bash
# LICENSE UPL 1.0
#
# Copyright (c) 1982-2018 Oracle and/or its affiliates. All rights reserved.
# 
# Since: November, 2016
# Author: gerald.venzl@oracle.com
# Description: Sets the password for sys, system and pdb_admin
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

# If empty default password: sys$ORACLE_SID

if [ $# -eq 0 ]; then
   ORACLE_PWD=sys`grep $ORACLE_HOME /etc/oratab | cut -d: -f1`
else
   ORACLE_PWD=$1
fi 

ORACLE_SID="`grep $ORACLE_HOME /etc/oratab | cut -d: -f1`"
ORAENV_ASK=NO
source oraenv

sqlplus / as sysdba << EOF
      ALTER USER SYS IDENTIFIED BY "$ORACLE_PWD";
      ALTER USER SYSTEM IDENTIFIED BY "$ORACLE_PWD";
      exit;
EOF


echo "ORACLE PASSWORD FOR SYS: $ORACLE_PWD";

