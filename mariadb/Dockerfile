FROM mariadb:10.5@sha256:a1988653a7aa0b76a2f2034754bb25ebdcd9030fadc5118f9f837a197a803720
LABEL org.label-schema.schema-version="1.0.0-rc1"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="db"

RUN rm /etc/mysql/my.cnf && rm /etc/mysql/mariadb.cnf && rm -rf /etc/mysql/mariadb.conf.d
COPY ee.cnf  /etc/mysql/conf.d/ee.cnf
COPY my.cnf  /etc/mysql/