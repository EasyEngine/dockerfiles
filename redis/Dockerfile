FROM redis:6.2.6@sha256:54ee15a0b0d2c661d46b9bfbf55b181f9a4e7ddf8bf693eec5703dac2c0f5546

LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="redis"

RUN mkdir -p /var/log/redis; \
	chown -R redis: /var/log/redis
COPY redis.conf /usr/local/etc/redis/redis.conf
COPY purge_all_cache.lua /data/purge_all_cache.lua
