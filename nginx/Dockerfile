FROM openresty/openresty:1.25.3.2-buster
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="nginx"

# Copy EasyEngine nginx configuration files
RUN mkdir -p /var/log/nginx; \
    mkdir -p /usr/local/openresty/nginx/conf/conf.d
COPY conf /usr/local/openresty/nginx/conf
COPY bashrc /root/.bashrc
WORKDIR /var/www/htdocs
RUN usermod -s /bin/bash www-data
USER www-data
EXPOSE 80
