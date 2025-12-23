FROM alpine

RUN apk update && apk add logrotate

COPY easyengine.conf /etc/logrotate.d/easyengine

COPY load-and-sleep.sh /

RUN chmod 644 /etc/logrotate.d/easyengine

RUN chmod +x /load-and-sleep.sh

ENTRYPOINT ["/load-and-sleep.sh"]
