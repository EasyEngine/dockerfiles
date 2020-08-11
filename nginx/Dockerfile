# FROM openresty/openresty:1.17.8.2-buster
FROM openresty/openresty@sha256:65d18b84c5dc2c03ac1623a73986e2fc4b9f5bcfb792f36a0f4cf12525177bbf
LABEL org.label-schema.schema-version="1.0.0-rc1"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="nginx"

# Copy EasyEngine nginx configuration files
RUN mkdir -p /var/log/nginx; \
    mkdir -p /usr/local/openresty/nginx/conf/conf.d
COPY conf /usr/local/openresty/nginx/conf
EXPOSE 80
