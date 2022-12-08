FROM mariadb:10.10@sha256:a98834606bea049d3094d0d90964eb749d9a10c46f60e58e67ca75a6a155c1ad
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="db"

RUN rm /etc/mysql/my.cnf && rm /etc/mysql/mariadb.cnf && rm -rf /etc/mysql/mariadb.conf.d
COPY ee.cnf  /etc/mysql/conf.d/ee.cnf
COPY my.cnf  /etc/mysql/
