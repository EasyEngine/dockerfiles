FROM php:7.2-fpm@sha256:a8d1ebf6390aa47574fd8aec875d907a4fa1169de8c88bd256890921e6454436

LABEL maintainer="Devarshi Sathiya <devarshisathiya5@gmail.com>, Riddhesh Sanghvi <riddhesh237@gmail.com>"
LABEL org.label-schema.schema-version="1.0.0-rc1"
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
		libmcrypt-dev \
		libmemcached-dev \
		libxml2-dev \
		libpng-dev \
		libzip-dev \
		libssl-dev \
		libicu-dev \
		unzip \
		vim \
		zip

RUN pecl install imagick; \
	pecl install memcached; \
	pecl install mcrypt-1.0.3; \
	pecl install redis; \
	docker-php-ext-configure gd --with-freetype-dir=/usr/include/freetype2 --with-png-dir=/usr/include --with-jpeg-dir=/usr/include; \
	docker-php-ext-configure zip; \
	docker-php-ext-install gd; \
	PHP_OPENSSL=yes docker-php-ext-configure imap --with-kerberos --with-imap-ssl; \
	echo "extension=memcached.so" >> /usr/local/etc/php/conf.d/memcached.ini; \
	docker-php-ext-install imap; \
	docker-php-ext-install mysqli; \
	docker-php-ext-install pdo_mysql; \
	docker-php-ext-install opcache; \
	docker-php-ext-install soap; \
	docker-php-ext-install intl; \
	docker-php-ext-install zip; \
	docker-php-ext-install exif; \
	docker-php-ext-enable imagick mcrypt redis; \
	docker-php-ext-install bcmath; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*;

RUN	mkdir -p /usr/src/php/ext; \
	cd /usr/src/php/ext/; \
	curl -sSL -o php7.zip https://github.com/websupport-sk/pecl-memcache/archive/NON_BLOCKING_IO_php7.zip; \
	unzip php7.zip; \
	mv pecl-memcache-NON_BLOCKING_IO_php7 memcache; \
	rm -rf /tmp/pecl-memcache-php7 /usr/src/php/ext/php7.zip; \
	docker-php-ext-configure memcache --with-php-config=/usr/local/bin/php-config; \
	docker-php-ext-install memcache;

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

WORKDIR /var/www/htdocs
USER www-data

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm"]
