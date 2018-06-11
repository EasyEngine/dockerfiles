#!/bin/bash
set -euo pipefail

U_ID=${USER_ID}
G_ID=${GROUP_ID}

wwwdata_uid=$(id -u www-data)
if [[ "$U_ID" -ne 0 &&  "$wwwdata_uid" -ne $U_ID ]];then
	usermod -u $U_ID www-data
	groupmod -g $G_ID www-data
	chown -R www-data:www-data /var/
fi

exec "$@"
