FROM jwilder/nginx-proxy:latest
LABEL org.label-schema.schema-version="1.0.0-rc1"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="nginx-proxy"

COPY docker-entrypoint.sh /app/
COPY nginx.tmpl /app/
COPY nginx.conf /etc/nginx/nginx.conf

RUN apt-get update \
    && apt-get install --no-install-recommends apache2-utils -y && rm -rf /var/lib/apt/lists/*

RUN chmod +x /app/docker-entrypoint.sh
