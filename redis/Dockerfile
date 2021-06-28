FROM redis:6.2.4@sha256:7e2c6181ad5c425443b56c7c73a9cd6df24a122345847d1ea9bb86a5afc76325

LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="redis"

RUN mkdir -p /var/log/redis; \
	chown -R redis: /var/log/redis
COPY redis.conf /usr/local/etc/redis/redis.conf
COPY purge_all_cache.lua /data/purge_all_cache.lua
