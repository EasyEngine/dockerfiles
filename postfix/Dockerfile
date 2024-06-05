FROM debian:10.13-slim

LABEL maintainer="Riddhesh Sanghvi <riddhesh237@gmail.com>"
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="postfix"


# Build and install Postfix
# https://git.launchpad.net/postfix/tree/debian/rules?id=94dfb9850484db5f47958eaa86f958857ab9834c
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends --no-install-suggests \
            openssl \
            m4 \
            inetutils-syslogd \
            ca-certificates \
 && update-ca-certificates \
    \
 # Install Postfix dependencies
 && apt-get install -y --no-install-recommends --no-install-suggests \
            libpcre3 libicu63 \
            libdb5.3 libpq5 libmariadb3 libmariadb-dev-compat libsqlite3-0 \
            libsasl2-2 \
            libldap-2.4 \
            libsasl2-modules \
    \
 # Install tools for building
 && toolDeps=" \
        curl make gcc g++ libc-dev \
    " \
 && apt-get install -y --no-install-recommends --no-install-suggests \
            $toolDeps \
    \
 # Install Postfix build dependencies
 && buildDeps=" \
        libssl-dev \
        libpcre3-dev libicu-dev \
        libdb-dev libpq-dev libmariadbclient-dev libsqlite3-dev \
        libsasl2-dev \
        libldap2-dev \
    " \
 && apt-get install -y --no-install-recommends --no-install-suggests \
            $buildDeps

 # Download and prepare Postfix sources
RUN curl -fL -o /tmp/postfix.tar.gz \
         http://ftp.porcupine.org/mirrors/postfix-release/official/postfix-3.8.3.tar.gz \
 && tar -xzf /tmp/postfix.tar.gz -C /tmp/

 # Build Postfix from sources
RUN cd /tmp/postfix-* \
    && sed -i -e "s:/usr/local/:/usr/:g" conf/master.cf \
    && make makefiles \
         CCARGS="-DHAS_SHL_LOAD -DUSE_TLS \
                 -DHAS_PCRE $(pcre-config --cflags) \
                 -DHAS_PGSQL -I/usr/include/postgresql \
                 -DHAS_MYSQL $(mysql_config --include) \
                 -DHAS_SQLITE -I/usr/include \
                 -DHAS_LDAP -I/usr/include \
                 -DUSE_CYRUS_SASL -I/usr/include/sasl \
                 -DUSE_SASL_AUTH -DDEF_SASL_SERVER=\\\"dovecot\\\" \
                 -DUSE_LDAP_SASL" \
         AUXLIBS="-lssl -lcrypto -lsasl2" \
         AUXLIBS_PCRE="$(pcre-config --libs)" \
         AUXLIBS_PGSQL="-lpq" \
         AUXLIBS_MYSQL="$(mysql_config --libs)" \
         AUXLIBS_SQLITE="-lsqlite3 -lpthread" \
         AUXLIBS_LDAP="-lldap -llber" \
         shared=yes \
         dynamicmaps=yes \
         pie=yes \
         daemon_directory=/usr/lib/postfix \
         shlibs_directory=/usr/lib/postfix \
         # No documentation included to keep image size smaller
         manpage_directory=/tmp/man \
         readme_directory=/tmp/readme \
         html_directory=/tmp/html \
 && make

 # Create Postfix user and groups
RUN addgroup --system --gid 91 postfix \
 && adduser --system --uid 90 --disabled-password \
            --no-create-home --home /var/spool/postfix \
            --ingroup postfix --gecos postfix \
            postfix \
 && adduser postfix mail \
 && addgroup --system --gid 93 postdrop \
 && adduser --system --uid 92 --disabled-password --shell /sbin/nologin \
            --no-create-home --home /var/mail/domains \
            --ingroup postdrop --gecos vmail \
            vmail \
    \
 # Install Postfix
 && cd /tmp/postfix-* \
 && make upgrade \
 # Always execute these binaries under postdrop group
 && chmod g+s /usr/sbin/postdrop \
              /usr/sbin/postqueue \
 # Ensure spool dir has correct rights
 && install -d -o postfix -g postfix /var/spool/postfix \
 # Fix removed directories in default configuration
 && sed -i -e 's,^manpage_directory =.*,manpage_directory = /dev/null,' \
           -e 's,^readme_directory =.*,readme_directory = /dev/null,' \
           -e 's,^html_directory =.*,html_directory = /dev/null,' \
        /etc/postfix/main.cf

 # Prepare directories for drop-in configuration files
RUN cd /tmp/postfix-* \
 && install -d /etc/postfix/main.cf.d \
 && install -d /etc/postfix/master.cf.d \
 # Pregenerate Diffie-Hellman parameters (heavy operation)
 && openssl dhparam -out /etc/postfix/dh2048.pem 2048 \
 # Tweak TLS/SSL settings to achieve A grade
 && echo "\n\
        \n# TLS PARAMETERS\
        \n#\
        \ntls_ssl_options = NO_COMPRESSION\
        \ntls_high_cipherlist = ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256\
        \n\
        \n# SMTP TLS PARAMETERS (outgoing connections)\
        \n#\
        \nsmtp_tls_security_level = may\
        \nsmtp_tls_CApath = /etc/ssl/certs\
        \n\
        \n# SMTPD TLS PARAMETERS (incoming connections)\
        \n#\
        \nsmtpd_tls_security_level = may\
        \nsmtpd_tls_ciphers = high\
        \nsmtpd_tls_mandatory_ciphers = high\
        \nsmtpd_tls_exclude_ciphers = aNULL, LOW, EXP, MEDIUM, ADH, AECDH, MD5, DSS, ECDSA, CAMELLIA128, 3DES, CAMELLIA256, RSA+AES, eNULL\
        \nsmtpd_tls_dh1024_param_file = /etc/postfix/dh2048.pem\
        \nsmtpd_tls_CApath = /etc/ssl/certs\
        \nsmtpd_tls_cert_file = /etc/ssl/postfix/server.crt\
        \nsmtpd_tls_key_file = /etc/ssl/postfix/server.key\
    " >> /etc/postfix/main.cf

EXPOSE 25

CMD ["postfix", "start-fg"]
