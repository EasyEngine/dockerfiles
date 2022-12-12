FROM openresty/openresty:1.21.4.1-4-buster@sha256:9be444a283344aec2d499682c7ab9d342d06245632c8e71a0c1c37d19d11b436
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="nginx"

# Copy EasyEngine nginx configuration files
RUN mkdir -p /var/log/nginx; \
    mkdir -p /usr/local/openresty/nginx/conf/conf.d
COPY conf /usr/local/openresty/nginx/conf
EXPOSE 80
