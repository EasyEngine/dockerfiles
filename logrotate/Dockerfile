FROM alpine

RUN apk update && apk add logrotate

COPY easyengine.conf /etc/logrotate.d/easyengine

WORKDIR /etc/logrotate.d
