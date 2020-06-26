FROM openresty/openresty@sha256:12bd5565639edec7f92cf04ca4bf635b0cba974130d182a71f8ab1fa79d59398
LABEL org.label-schema.schema-version="1.0.0-rc1"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="nginx"

# Copy EasyEngine nginx configuration files
RUN mkdir -p /var/log/nginx; \
    mkdir -p /usr/local/openresty/nginx/conf/conf.d
COPY conf /usr/local/openresty/nginx/conf
EXPOSE 80
