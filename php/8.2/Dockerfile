FROM php:8.2-fpm@sha256:90ef8a254ccac54c7a4d1ddc34627a4d6dc596ca1461ef1fb8db1741fbd0c92e

LABEL maintainer="Riddhesh Sanghvi <riddhesh237@gmail.com>, Devarshi Sathiya <devarshisathiya5@gmail.com>"
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="php"

RUN set -ex; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		imagemagick \
		less \
		mariadb-client msmtp \
		libc-client-dev \
		libfreetype6-dev \
		libjpeg-dev \
		libjpeg62-turbo-dev \
		libkrb5-dev \
		libmagickwand-dev \
		libgraphicsmagick1-dev \
		libmcrypt-dev \
		libicu-dev \
		libmemcached-dev \
		libxml2-dev \
		libpng-dev \
		libzip-dev \
		libssl-dev \
		libgmp-dev \
		unzip \
		vim \
		zip

RUN pecl install imagick; \
	pecl install memcached; \
	pecl install redis; \
	pecl install apcu; \
	# https://github.com/php/pecl-encryption-mcrypt/issues/7#issuecomment-1050994596
	pecl install -n mcrypt; \
	pecl install gmagick-2.0.6RC1; \
	pecl install timezonedb; \
	docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
	docker-php-ext-configure zip; \
	docker-php-ext-install gd; \
	PHP_OPENSSL=yes docker-php-ext-configure imap --with-kerberos --with-imap-ssl; \
	docker-php-ext-install imap; \
	docker-php-ext-install mysqli; \
	docker-php-ext-install pdo_mysql; \
	docker-php-ext-install opcache; \
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
	docker-php-ext-enable imagick mcrypt redis timezonedb apcu; \
	echo "extension=memcached.so" >> /usr/local/etc/php/conf.d/memcached.ini; \
	echo "extension=gmagick.so" >> /usr/local/etc/php/conf.d/gmagick.ini; \
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

RUN latest_build=$(curl -s https://download.newrelic.com/php_agent/release/ | grep 'linux.tar.gz' | sed 's/.*"\(.*\)".*/\1/') && \
curl -L "https://download.newrelic.com$latest_build" | tar -C /tmp -zx && \
export NR_INSTALL_USE_CP_NOT_LN=1 && \
export NR_INSTALL_SILENT=1 && \
/tmp/newrelic-php5-*/newrelic-install install && \
rm -rf /tmp/newrelic-php5-* /tmp/nrinstall*

ENV NR_PORT=/run/newrelic/newrelic.sock

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
COPY newrelic.ini /usr/local/etc/php/conf.d/newrelic.ini
COPY newrelic.ini /data/newrelic.ini

WORKDIR /var/www/htdocs
USER www-data

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm"]
