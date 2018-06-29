FROM php:7.2-fpm

RUN set -ex; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		imagemagick \
		less \
		libfreetype6-dev \
		libjpeg-dev \
		libjpeg62-turbo-dev \
		libmagickwand-dev \
		libmcrypt-dev \
		libmemcached-dev \
		libpng-dev \
		libzip-dev \
		mysql-client \
		ssmtp \
		unzip \
		zip

RUN pecl install imagick memcached; \
	printf "\n" | pecl install mcrypt-1.0.1; \
	printf "\n" | pecl install redis; \
	docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr; \
	docker-php-ext-configure zip --with-libzip; \
	docker-php-ext-configure --with-php-config=/usr/local/bin/php-config; \
	docker-php-ext-install gd mysqli opcache zip; \
	docker-php-ext-enable imagick mcrypt; \
	echo "extension=memcached.so" >> /usr/local/etc/php/conf.d/memcached.ini; \
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
		echo 'path: /var/www/html'; \
		} > /etc/wp-cli/config.yml

RUN echo "mailhub=mail:1025\nUseTLS=NO\nFromLineOverride=YES" > /etc/ssmtp/ssmtp.conf
COPY bashrc /root/.bashrc
COPY bashrc /var/www/.bashrc
COPY docker-entrypoint.sh /usr/local/bin/
VOLUME /var/www/html

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm"]
