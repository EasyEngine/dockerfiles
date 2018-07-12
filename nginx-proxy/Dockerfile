FROM jwilder/nginx-proxy:latest

COPY docker-entrypoint.sh /app/
COPY nginx.tmpl /app/

RUN apt-get update \
    && apt-get install apache2-utils -y

RUN chmod +x /app/docker-entrypoint.sh

