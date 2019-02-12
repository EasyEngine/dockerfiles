# alpine:latest at 2019-01-30T19:08:47IST
FROM alpine@sha256:46e71df1e5191ab8b8034c5189e325258ec44ea739bba1e5645cff83c9048ff1

ARG NR_VERSION=8.5.0.235
ENV NR_PORT=/run/newrelic/newrelic.sock
ENV NR_FILE_NAME=newrelic-php5-$NR_VERSION-linux-musl
ENV NR_FILE_URL=https://download.newrelic.com/php_agent/archive/$NR_VERSION/$NR_FILE_NAME.tar.gz

RUN set -ex; \
    apk --no-cache add curl; \
    curl --connect-timeout 10 -o nr.tar.gz -fSL $NR_FILE_URL; \
    tar -xf nr.tar.gz; \
    cp $NR_FILE_NAME/daemon/newrelic-daemon.x64 /usr/local/bin/newrelic-daemon; \
    mkdir -p /var/log/newrelic /run/newrelic; \
    rm -rf newrelic-php5* nr.tar.gz;

CMD ["sh", "-c", "/usr/local/bin/newrelic-daemon -f --port ${NR_PORT}"]
