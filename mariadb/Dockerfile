FROM mariadb:10.11
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="db"

RUN rm /etc/mysql/my.cnf && rm /etc/mysql/mariadb.cnf
COPY ee.cnf  /etc/mysql/conf.d/ee.cnf
COPY my.cnf  /etc/mysql/
