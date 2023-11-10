#!/bin/bash
set -euo pipefail -o nounset

if [[ -z "${NEWRELIC_LICENSE_KEY:-}" ]] || [[ -z "${NEWRELIC_APPNAME:-}" ]]; then
    :
else
    cp /data/newrelic.ini /usr/local/etc/php/conf.d/newrelic.ini
    sed -i -e "s/\"REPLACE_WITH_REAL_KEY\"/\"$NEWRELIC_LICENSE_KEY\"/" \
    -e "s/newrelic.appname = \"PHP Application\"/newrelic.appname = \"$NEWRELIC_APPNAME\"/" \
    /usr/local/etc/php/conf.d/newrelic.ini
fi

exec "$@"
