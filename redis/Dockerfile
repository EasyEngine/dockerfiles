FROM redis:7.2.5

LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="redis"

RUN mkdir -p /var/log/redis; \
	chown -R redis: /var/log/redis
COPY redis.conf /usr/local/etc/redis/redis.conf
COPY purge_all_cache.lua /data/purge_all_cache.lua
