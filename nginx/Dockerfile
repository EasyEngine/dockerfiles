FROM openresty/openresty:stretch
LABEL org.label-schema.schema-version="1.0.0-rc1"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="nginx"

# Copy EasyEngine nginx configuration files
RUN mkdir -p /var/log/nginx
COPY conf /usr/local/openresty/nginx/conf
COPY default.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
