FROM jwilder/nginx-proxy:1.5.2@sha256:404906fb004005e6b5829a866972e2a35a4afcef4bf5c89b16dd2869d47ffe38
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="nginx-proxy"

COPY nginx.tmpl /app/
COPY nginx.conf /etc/nginx/nginx.conf
COPY version.conf /version.conf

RUN apt-get update \
    && apt-get install --no-install-recommends apache2-utils -y && rm -rf /var/lib/apt/lists/*

RUN chmod +x /app/docker-entrypoint.sh
RUN rm -rf /var/log/nginx/access.log /var/log/nginx/error.log && touch /var/log/nginx/access.log /var/log/nginx/error.log
