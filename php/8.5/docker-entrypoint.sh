#!/bin/bash
set -euo pipefail -o nounset

nr_ini=/usr/local/etc/php/conf.d/newrelic.ini
warn() { echo "docker-entrypoint: $*" >&2 || true; }
# The values land in a double-quoted ini string (where PHP expands ${...}) and a sed replacement.
nr_value_ok() { [[ $1 != *[\"\\\$]* && $1 != *[[:cntrl:]]* ]]; }
nr_sed_escape() { printf '%s' "$1" | sed 's/[\\|&]/\\&/g'; }
# nr_set <key regex> <line>: replace the key's lines, or append one when the ini has none.
nr_set() {
    local last
    last=$(grep "^$1[[:space:]]*=" "$nr_ini" | tail -n 1)
    if [[ -n "$last" ]]; then
        # PHP uses the last assignment, so only that one decides whether to write.
        [[ "$last" == "$2" ]] && return
        sed -i --follow-symlinks "s|^$1[[:space:]]*=.*|$(nr_sed_escape "$2")|" "$nr_ini"
    else
        if [[ -s "$nr_ini" && -n "$(tail -c 1 "$nr_ini")" ]]; then
            printf '\n' >> "$nr_ini" || return
        fi
        printf '%s\n' "$2" >> "$nr_ini"
    fi
}
# The app name is set only over the image's placeholder or when missing, so a name set by hand stays.
nr_set_appname() {
    local last placeholder='^newrelic\.appname[[:space:]]*=[[:space:]]*"?PHP Application"?[[:space:]]*$'
    last=$(grep "^newrelic\.appname[[:space:]]*=" "$nr_ini" | tail -n 1)
    [[ -z "$last" || "$last" =~ $placeholder ]] || return 0
    nr_set 'newrelic\.appname' "newrelic.appname = \"$NEWRELIC_APPNAME\""
}

if [[ -z "${NEWRELIC_LICENSE_KEY:-}" ]] || [[ -z "${NEWRELIC_APPNAME:-}" ]]; then
    :
elif ! nr_value_ok "$NEWRELIC_LICENSE_KEY" || ! nr_value_ok "$NEWRELIC_APPNAME"; then
    warn "NEWRELIC_LICENSE_KEY or NEWRELIC_APPNAME has a quote, backslash, \$ or control character, $nr_ini left as is"
else
    if [[ -L "$nr_ini" && ! -e "$nr_ini" ]]; then
        warn "$nr_ini is a dangling symlink, left as is"
    # A site config made from a php-fpm zip (ee site update --php) has no newrelic.ini: start from the image's copy instead of failing.
    elif [[ ! -e "$nr_ini" ]] && ! cp /data/newrelic.ini "$nr_ini"; then
        warn "could not create $nr_ini, New Relic stays off"
    fi
    # The license is set by key, not by placeholder, so a changed key reaches an ini written on an earlier start.
    if [[ -f "$nr_ini" ]] && ! { nr_set 'newrelic\.license' "newrelic.license = \"$NEWRELIC_LICENSE_KEY\"" && nr_set_appname; }; then
        warn "could not write the New Relic license to $nr_ini"
    fi
fi

exec "$@"
