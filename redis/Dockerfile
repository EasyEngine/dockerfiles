FROM redis:7.0.5@sha256:dfeb5451fce377ab47c5bb6b6826592eea534279354bbfc3890c0b5e9b57c763

LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="redis"

RUN mkdir -p /var/log/redis; \
	chown -R redis: /var/log/redis
COPY redis.conf /usr/local/etc/redis/redis.conf
COPY purge_all_cache.lua /data/purge_all_cache.lua
