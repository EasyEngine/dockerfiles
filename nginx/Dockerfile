FROM openresty/openresty:1.21.4.1-buster@sha256:24ecf9dd29a1fd884a123c92178bc2e2d74b5c8aa2e38e5bf01a501a76dd8241
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="nginx"

# Copy EasyEngine nginx configuration files
RUN mkdir -p /var/log/nginx; \
    mkdir -p /usr/local/openresty/nginx/conf/conf.d
COPY conf /usr/local/openresty/nginx/conf
EXPOSE 80
