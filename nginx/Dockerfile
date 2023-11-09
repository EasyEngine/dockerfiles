FROM openresty/openresty:1.21.4.2-buster@sha256:c1ecc876f6339696b1d9b9a3f0735ff814f758e5eb966bdfc26966172e27d0b8
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="nginx"

# Copy EasyEngine nginx configuration files
RUN mkdir -p /var/log/nginx; \
    mkdir -p /usr/local/openresty/nginx/conf/conf.d
COPY conf /usr/local/openresty/nginx/conf
EXPOSE 80
