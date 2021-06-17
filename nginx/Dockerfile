# FROM openresty/openresty:1.19.3.2-1-buster
FROM openresty/openresty@sha256:b8652cab08d74ca44479c31db75008a8a40c9c3b186fa44d7f03aec721e29066
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="nginx"

# Copy EasyEngine nginx configuration files
RUN mkdir -p /var/log/nginx; \
    mkdir -p /usr/local/openresty/nginx/conf/conf.d
COPY conf /usr/local/openresty/nginx/conf
EXPOSE 80
