# alpine:latest at 2023-11-10T14:09:58IST
FROM alpine@sha256:eece025e432126ce23f223450a0326fbebde39cdf496a85d8c016293fc851978

LABEL maintainer="Riddhesh Sanghvi <riddhesh237@gmail.com>"
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="newrelic-daemon"

ENV NR_PORT=/run/newrelic/newrelic.sock

RUN  set -ex; \
    apk --no-cache add curl; \
    export NR_FILE_URL="https://download.newrelic.com$(curl -s https://download.newrelic.com/php_agent/release/ | grep 'linux-musl.tar.gz' | sed 's/.*"\(.*\)".*/\1/')"; \
    curl --connect-timeout 10 -o nr.tar.gz -fSL $NR_FILE_URL; \
    tar -xf nr.tar.gz; \
    cp newrelic-php5-*/daemon/newrelic-daemon.x64 /usr/local/bin/newrelic-daemon; \
    mkdir -p /var/log/newrelic /run/newrelic; \
    rm -rf newrelic-php5* nr.tar.gz;

CMD ["sh", "-c", "/usr/local/bin/newrelic-daemon -f --port ${NR_PORT}"]
