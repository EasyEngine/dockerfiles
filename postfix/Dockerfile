FROM debian:stretch-slim

LABEL maintainer="Dharmin Shah <dharminshah175@gmail.com>"

ENV DEBIAN_FRONTEND noninteractive

# Update
RUN apt-get update

RUN apt-get -y install supervisor postfix mailutils
RUN openssl genrsa -des3 -out easyengine.key -passout pass:easyengine 2048 \
    && chmod 600 easyengine.key \
    && openssl req -new -key easyengine.key -passin pass:easyengine -out easyengine.csr -subj "/C=US/ST=NY/L=Maspeth/O=EasyEngine/OU=DevOps/CN=easyengine" \
    && openssl x509 -req -days 365 -in easyengine.csr -signkey easyengine.key -passin pass:easyengine -out easyengine.crt \
    && openssl rsa -in easyengine.key -passin pass:easyengine -out easyengine.key.nopass  \
    && mv easyengine.key.nopass easyengine.key \
    && openssl req -new -x509 -extensions v3_ca -keyout cakey.pem -passout pass:easyengine -out cacert.pem -days 3650 -subj "/C=US/ST=NY/L=Maspeth/O=EasyEngine/OU=DevOps/CN=easyengine" \
    && chmod 600 easyengine.key \
    && chmod 600 cakey.pem \
    && mv easyengine.key /etc/ssl/private/ \
    && mv easyengine.crt /etc/ssl/certs/ \
    && mv cakey.pem /etc/ssl/private/ \
    && mv cacert.pem /etc/ssl/certs/ \
    && postconf -e 'smtpd_tls_auth_only = no' \
    && postconf -e 'smtp_use_tls = yes' \
    && postconf -e 'smtpd_use_tls = yes' \
    && postconf -e 'smtp_tls_note_starttls_offer = yes' \
    && postconf -e 'smtpd_tls_key_file = /etc/ssl/private/easyengine.key' \
    && postconf -e 'smtpd_tls_cert_file = /etc/ssl/certs/easyengine.crt' \
    && postconf -e 'smtpd_tls_CAfile = /etc/ssl/certs/cacert.pem' \
    && postconf -e 'smtpd_tls_loglevel = 1' \
    && postconf -e 'smtpd_tls_received_header = yes' \
    && postconf -e 'smtpd_tls_session_cache_timeout = 3600s' \
    && postconf -e 'tls_random_source = dev:/dev/urandom' \
    && postconf -e 'myhostname = mail.example.com'

RUN echo '[supervisord]\n\
    nodaemon=true\n\
    [program:postfix]\n\
    command=/opt/postfix.sh\n\
'> /etc/supervisor/conf.d/supervisord.conf

RUN echo '#!/bin/bash\n\
    service postfix start\n\
    tail -f /var/log/mail.log\n\
    ' >> /opt/postfix.sh

RUN chmod +x /opt/postfix.sh

CMD /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
