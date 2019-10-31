FROM openresty/openresty:stretch
LABEL maintainer="Mriyam Tamuli <mbtamuli@gmail.com>, Riddhesh Sanghvi <riddheshsanghvi96@gmail.com>"
LABEL org.label-schema.schema-version="1.0.0-rc1"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="nginx"

# Copy EasyEngine nginx configuration files
RUN mkdir -p /var/log/nginx; \
    mkdir -p /usr/local/openresty/nginx/conf/conf.d
COPY conf /usr/local/openresty/nginx/conf
EXPOSE 80
