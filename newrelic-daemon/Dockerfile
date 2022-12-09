# alpine:latest at 2022-12-08T10:45:13IST
FROM alpine@sha256:8914eb54f968791faf6a8638949e480fef81e697984fba772b3976835194c6d4

LABEL maintainer="Riddhesh Sanghvi <riddhesh237@gmail.com>"
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="newrelic-daemon"

ARG NR_VERSION=10.3.0.315
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
