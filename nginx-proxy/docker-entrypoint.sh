#!/bin/bash
set -e

# Warn if the DOCKER_HOST socket does not exist
if [[ $DOCKER_HOST = unix://* ]]; then
	socket_file=${DOCKER_HOST#unix://}
	if ! [ -S $socket_file ]; then
		cat >&2 <<-EOT
			ERROR: you need to share your Docker host socket with a volume at $socket_file
			Typically you should run your jwilder/nginx-proxy with: \`-v /var/run/docker.sock:$socket_file:ro\`
			See the documentation at http://git.io/vZaGJ
		EOT
		socketMissing=1
	fi
fi

# https://github.com/nginx-proxy/nginx-proxy/blob/main/app/docker-entrypoint.sh
function _setup_dhparam() {
	# DH params will be supplied for nginx here:
	local DHPARAM_FILE='/etc/nginx/dhparam/dhparam.pem'

	# Should be 2048, 3072, or 4096 (default):
	local FFDHE_GROUP="${DHPARAM_BITS:=4096}"

	# DH params may be provided by the user (rarely necessary)
	if [[ -f ${DHPARAM_FILE} ]]; then
		echo 'Warning: A custom dhparam.pem file was provided. Best practice is to use standardized RFC7919 DHE groups instead.' >&2
		return 0
	elif _parse_true "${DHPARAM_SKIP:=false}"; then
		echo 'Skipping Diffie-Hellman parameters setup.'
		return 0
	elif _parse_false "${DHPARAM_GENERATION:=true}"; then
		echo 'Warning: The DHPARAM_GENERATION environment variable is deprecated, please consider using DHPARAM_SKIP set to true instead.' >&2
		echo 'Skipping Diffie-Hellman parameters setup.'
		return 0
	elif [[ ! ${DHPARAM_BITS} =~ ^(2048|3072|4096)$ ]]; then
		echo "ERROR: Unsupported DHPARAM_BITS size: ${DHPARAM_BITS}. Use: 2048, 3072, or 4096 (default)." >&2
		exit 1
	fi

	echo 'Setting up DH Parameters..'

	# Use an existing pre-generated DH group from RFC7919 (https://datatracker.ietf.org/doc/html/rfc7919#appendix-A):
	local RFC7919_DHPARAM_FILE="/app/dhparam/ffdhe${FFDHE_GROUP}.pem"

	# Provide the DH params file to nginx:
	cp "${RFC7919_DHPARAM_FILE}" "${DHPARAM_FILE}"
}

# Compute the DNS resolvers for use in the templates - if the IP contains ":", it's IPv6 and must be enclosed in []
export RESOLVERS=$(awk '$1 == "nameserver" {print ($2 ~ ":")? "["$2"]": $2}' ORS=' ' /etc/resolv.conf | sed 's/ *$//g')
if [ "x$RESOLVERS" = "x" ]; then
    echo "Warning: unable to determine DNS resolvers for nginx" >&2
    unset RESOLVERS
fi

# If the user has run the default command and the socket doesn't exist, fail
if [ "$socketMissing" = 1 -a "$1" = forego -a "$2" = start -a "$3" = '-r' ]; then
	exit 1
fi

_setup_dhparam

exec "$@"
