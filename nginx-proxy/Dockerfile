FROM jwilder/nginx-proxy:latest

COPY docker-entrypoint.sh /app/
COPY nginx.tmpl /app/
RUN chmod +x /app/docker-entrypoint.sh

