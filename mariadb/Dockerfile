FROM mariadb:10.8.2@sha256:490f01279be1452f12f497a592112cb960cf0500938dbf0ea3f0135cb6728d3d
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="db"

RUN rm /etc/mysql/my.cnf && rm /etc/mysql/mariadb.cnf
COPY ee.cnf  /etc/mysql/conf.d/ee.cnf
COPY my.cnf  /etc/mysql/
