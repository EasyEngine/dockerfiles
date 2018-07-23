FROM openresty/openresty:stretch

# Copy EasyEngine nginx configuration files
RUN mkdir -p /var/log/nginx
COPY conf /usr/local/openresty/nginx/conf
EXPOSE 80
