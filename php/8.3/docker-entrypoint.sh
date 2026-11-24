#!/bin/bash
set -euo pipefail -o nounset

nr_ini=/usr/local/etc/php/conf.d/newrelic.ini
if [[ -z "${NEWRELIC_LICENSE_KEY:-}" ]] || [[ -z "${NEWRELIC_APPNAME:-}" ]]; then
    :
else
    # A site config made from a php-fpm zip (ee site update --php) has no newrelic.ini: start from the image's copy instead of failing.
    if [[ ! -f "$nr_ini" ]] && ! cp /data/newrelic.ini "$nr_ini"; then
        echo "docker-entrypoint: could not create $nr_ini, New Relic stays off" >&2
    fi
    if [[ -f "$nr_ini" ]]; then
        sed -i -e "s/\"REPLACE_WITH_REAL_KEY\"/\"$NEWRELIC_LICENSE_KEY\"/" \
        -e "s/newrelic.appname = \"PHP Application\"/newrelic.appname = \"$NEWRELIC_APPNAME\"/" \
        "$nr_ini" || echo "docker-entrypoint: could not write the New Relic license to $nr_ini" >&2
    fi
fi

exec "$@"
