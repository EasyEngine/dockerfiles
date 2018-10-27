FROM redis:5.0
RUN mkdir -p /var/log/redis; \
	chown -R redis: /var/log/redis
COPY redis.conf /usr/local/etc/redis/redis.conf
LABEL org.label-schema.schema-version="1.0.0-rc1"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="redis"