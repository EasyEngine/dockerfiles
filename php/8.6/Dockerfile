FROM php:8.6.0-fpm

LABEL maintainer="Riddhesh Sanghvi <riddhesh237@gmail.com>"
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="php"

RUN set -ex; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		imagemagick \
		less \
		mariadb-client msmtp \
		libfreetype6-dev \
		libjpeg-dev \
		libjpeg62-turbo-dev \
		libkrb5-dev \
		libmagickwand-dev \
		libgraphicsmagick1-dev \
		libmcrypt-dev \
		libicu-dev \
		libmemcached-dev \
		libonig-dev \
		libxml2-dev \
		libpng-dev \
		libzip-dev \
		libssl-dev \
		libgmp-dev \
		tmux \
		unzip \
		vim \
		zip

# imap is left out until it builds on 8.6, so its libc-client-dev from sury isn't needed.
#RUN curl -fsSL https://packages.sury.org/php/README.txt | bash && \
#	apt-get update && \
#	apt-get install -y libc-client-dev

# The 8.6 base image has no pecl (docker-library/php#1654), so extensions are built from source tarballs.
# The latest PECL releases of memcached, redis, apcu and imagick don't build on 8.6 yet; their upstream fixes are pinned instead.
RUN set -eux; \
	docker-php-source extract; \
	fetch_ext() { mkdir -p "/usr/src/php/ext/$1"; curl -fsSL "$2" | tar -xz -C "/usr/src/php/ext/$1" --strip-components=1; }; \
	fetch_ext memcached https://github.com/php-memcached-dev/php-memcached/archive/0b52d3657140750fa0eddd20cdbfc6edc8fbdadd.tar.gz; \
	fetch_ext redis https://github.com/phpredis/phpredis/archive/5b60b125aba347159b0c9c319296fbb3c5ed9214.tar.gz; \
	fetch_ext apcu https://github.com/krakjoe/apcu/archive/fb2c942552a3f5dab7f4dea4afb5cf0831222c57.tar.gz; \
	fetch_ext timezonedb https://pecl.php.net/get/timezonedb; \
	docker-php-ext-install memcached; \
	docker-php-ext-install redis; \
	docker-php-ext-install apcu; \
	docker-php-ext-install timezonedb; \
	# imagick 3.8.1 lacks the 8.6 fix (Imagick/imagick#795). Set the version from package.xml as pecl's packaging does;
	# a git source reports @PACKAGE_VERSION@, which WordPress rejects (it then falls back to GD).
	fetch_ext imagick https://github.com/Imagick/imagick/archive/55ed2e9fda264395636a2e27e51f31673f5566ab.tar.gz; \
	imagick_version=$(sed -n '/<version>/,/<\/version>/s/.*<release>\(.*\)<\/release>.*/\1/p' /usr/src/php/ext/imagick/package.xml); \
	sed -i "s/@PACKAGE_VERSION@/${imagick_version:?}/" /usr/src/php/ext/imagick/php_imagick.h; \
	docker-php-ext-install imagick; \
	# mcrypt and imap don't build on 8.6 yet, even from their upstream heads.
	# fetch_ext mcrypt https://pecl.php.net/get/mcrypt; \
	# docker-php-ext-install mcrypt; \
	# fetch_ext imap https://pecl.php.net/get/imap; \
	# docker-php-ext-configure imap --with-kerberos --with-imap-ssl; \
	# docker-php-ext-install imap; \
	docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
	docker-php-ext-configure zip; \
	docker-php-ext-install gd; \
	docker-php-ext-install mysqli; \
	docker-php-ext-install pdo_mysql; \
	docker-php-ext-install soap; \
	docker-php-ext-install intl; \
	docker-php-ext-install zip; \
	docker-php-ext-install exif; \
	docker-php-ext-install calendar; \
	docker-php-ext-install gmp; \
	docker-php-ext-install pcntl; \
	docker-php-ext-install shmop; \
	docker-php-ext-install sockets; \
	docker-php-ext-install sysvsem; \
	docker-php-ext-install sysvshm; \
	docker-php-ext-install bcmath; \
	# No longer built into the base image as of 8.6.
	docker-php-ext-install mbstring; \
	docker-php-source delete; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*;

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=2'; \
		echo 'opcache.fast_shutdown=1'; \
		echo 'opcache.enable_cli=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

# Donwload and install composer
RUN curl -sSL "https://getcomposer.org/installer" | php \
		&& mv composer.phar /usr/local/bin/composer

# Install wp-cli
RUN curl -O "https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar" \
		&& chmod +x wp-cli.phar \
		&& mv wp-cli.phar /usr/local/bin/wp

# Setup a config file
RUN mkdir -p /etc/wp-cli
RUN { \
		echo 'path: /var/www/htdocs'; \
		} > /etc/wp-cli/config.yml

RUN mkdir /usr/local/etc/misc && \
touch /usr/local/etc/misc/msmtprc && \
ln -s /usr/local/etc/misc/msmtprc /etc/msmtprc && \
chown www-data:www-data /usr/local/etc/misc/msmtprc && \
chown www-data:www-data /etc/msmtprc

#RUN latest_build=$(curl -s https://download.newrelic.com/php_agent/release/ | grep 'linux\.tar\.gz"' | head -n 1 | sed 's/.*"\(.*\)".*/\1/') && \
#curl -L "https://download.newrelic.com$latest_build" | tar -C /tmp -zx && \
#export NR_INSTALL_USE_CP_NOT_LN=1 && \
#export NR_INSTALL_SILENT=1 && \
#/tmp/newrelic-php5-*/newrelic-install install && \
#rm -rf /tmp/newrelic-php5-* /tmp/nrinstall*
#
#ENV NR_PORT=/run/newrelic/newrelic.sock

# Setup logs
RUN mkdir -p /var/log/php; \
	chown -R www-data: /var/log/php; \
	rm /usr/local/etc/php-fpm.d/*;
COPY php.ini /usr/local/etc/php/php.ini
COPY easyengine.conf /usr/local/etc/php-fpm.d/easyengine.conf

COPY expose_off.ini /usr/local/etc/php/conf.d/expose_off.ini
COPY bashrc /root/.bashrc
COPY bashrc /var/www/.bashrc
COPY docker-entrypoint.sh /usr/local/bin/
#COPY newrelic.ini /usr/local/etc/php/conf.d/newrelic.ini
#COPY newrelic.ini /data/newrelic.ini

WORKDIR /var/www/htdocs
RUN usermod -s /bin/bash www-data
USER www-data

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm"]
