FROM openresty/openresty:1.19.9.1-buster@sha256:41bbde7c101d691478424b5081162a5b65366625aed99e9cd519d8391fcb786e
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="nginx"

# Copy EasyEngine nginx configuration files
RUN mkdir -p /var/log/nginx; \
    mkdir -p /usr/local/openresty/nginx/conf/conf.d
COPY conf /usr/local/openresty/nginx/conf
EXPOSE 80
