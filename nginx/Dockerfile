FROM openresty/openresty:1.19.9.1-buster@sha256:c959c008c9a2f43e2833cd098dcfd5e1f761b682ac823b8619fd036e70eb691c
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="nginx"

# Copy EasyEngine nginx configuration files
RUN mkdir -p /var/log/nginx; \
    mkdir -p /usr/local/openresty/nginx/conf/conf.d
COPY conf /usr/local/openresty/nginx/conf
EXPOSE 80
