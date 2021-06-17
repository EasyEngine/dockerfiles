FROM mariadb:10.6@sha256:171746d0e04cf2e68776c76e9cd89fbde9e693842e98b570675000e7045d023a
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="db"

RUN rm /etc/mysql/my.cnf && rm /etc/mysql/mariadb.cnf && rm -rf /etc/mysql/mariadb.conf.d
COPY ee.cnf  /etc/mysql/conf.d/ee.cnf
COPY my.cnf  /etc/mysql/