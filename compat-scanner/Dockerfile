FROM composer:2.10.3 AS composer

WORKDIR /opt/compat-scanner
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --no-progress --no-cache --optimize-autoloader

# Calibration sample for estimate mode: ~1 MiB of WordPress core from a pinned, checksummed release.
ARG WP_VERSION=7.1.4
ARG WP_SHA256=881e53a4681ff2cd911651b11cccdede5ae477ddf0765af5d6a1a8b219a1d835
COPY calibration/select.php /tmp/select.php
RUN set -eux; \
    wget -q -O /tmp/wp.tar.gz "https://wordpress.org/wordpress-${WP_VERSION}.tar.gz"; \
    echo "${WP_SHA256}  /tmp/wp.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/wp.tar.gz -C /tmp wordpress/wp-includes; \
    php /tmp/select.php /tmp/wordpress/wp-includes /opt/compat-scanner/calibration; \
    rm -rf /tmp/wp.tar.gz /tmp/wordpress /tmp/select.php

FROM php:8.5-cli-alpine

LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="compat-scanner"

COPY --from=composer /opt/compat-scanner /opt/compat-scanner
COPY bin/ /opt/compat-scanner/bin/
COPY src/ /opt/compat-scanner/src/

USER 33:33
ENTRYPOINT ["php", "-d", "memory_limit=256M", "-d", "display_errors=stderr", "/opt/compat-scanner/bin/compat-scanner.php"]
