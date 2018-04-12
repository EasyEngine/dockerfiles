#!/bin/sh
EE_HOME=${HOST_HOME}
U_ID=${USER_ID}
G_ID=${GROUP_ID}
D_ID=${DOCKER_ID}

if [[ "$U_ID" -ne 0 ]];then
    groupadd -g $D_ID docker > /dev/null 2>&1
    useradd -u $U_ID ee > /dev/null 2>&1
    groupmod -g $G_ID ee > /dev/null 2>&1
    usermod -d $EE_HOME -u $U_ID ee > /dev/null 2>&1
    addgroup ee docker > /dev/null 2>&1
    addgroup ee sudo > /dev/null 2>&1
    echo "ee    ALL = NOPASSWD: ALL" >> /etc/sudoers
    gosu ee /usr/local/bin/ee4 $@
else
    /usr/local/bin/ee4 $@ --allow-root
fi
