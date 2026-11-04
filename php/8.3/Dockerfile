FROM php:8.3.36-fpm

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
		tmux \
		unzip \
		vim \
		zip

# Install libc-client-dev for imap from sury as not available for debian trixie
RUN curl -fsSL https://packages.sury.org/php/README.txt | bash && \
	apt-get update && \
	apt-get install -y libc-client-dev

# Extensions are built with PIE from Packagist/GitHub (not pecl.php.net); docker-php-ext-enable below enables them.
# CI passes its GITHUB_TOKEN as the optional `github_token` BuildKit secret for PIE's GitHub downloads; it never lands in a layer.
RUN --mount=type=secret,id=github_token \
	set -eu; \
	if [ -s /run/secrets/github_token ]; then \
		COMPOSER_AUTH="{\"github-oauth\":{\"github.com\":\"$(cat /run/secrets/github_token)\"}}"; \
		export COMPOSER_AUTH; \
	fi; \
	set -x; \
	curl -fsSL -o /usr/local/bin/pie https://github.com/php/pie/releases/download/1.5.2/pie.phar; \
	echo "fe70c59738cf56ec00a818cf9cb9593da171aac86f5f1f859995b8839dfd2cc7  /usr/local/bin/pie" | sha256sum -c -; \
	chmod +x /usr/local/bin/pie; \
	pie install --no-interaction --skip-enable-extension imagick/imagick:3.8.1; \
	pie install --no-interaction --skip-enable-extension php-memcached/php-memcached:3.4.0; \
	pie install --no-interaction --skip-enable-extension phpredis/phpredis:6.3.0; \
	pie install --no-interaction --skip-enable-extension apcu/apcu:5.1.28; \
	pie install --no-interaction --skip-enable-extension pecl/mcrypt:1.0.9; \
	# timezonedb stays unpinned: it only exists to ship newer tz data than PHP bundles, so it takes the latest release
	pie install --no-interaction --skip-enable-extension pecl/timezonedb; \
	# Record the exact commits PIE installed in the build log
	php -r 'foreach (glob("/root/.pie/*/pie.lock") as $f) foreach (json_decode(file_get_contents($f), true)["packages"] as $p) echo "PIE installed ", $p["name"], " ", $p["version"], " ", $p["dist"]["reference"] ?? $p["source"]["reference"] ?? "?", "\n";'; \
	rm -rf /usr/local/bin/pie /root/.pie /root/.composer; \
	# gmagick isn't on Packagist: build the source of its pecl 2.0.6RC1 release
	mkdir /tmp/gmagick; \
	curl -fsSL -o /tmp/gmagick.tar.gz https://github.com/vitoc/gmagick/archive/55423eec7715e89ad63334b35debf582b9566756.tar.gz; \
	echo "01fd8f0b0c7e92cd73b9165fa3ea4b247beb35bad8f6dda85d65e960607e97b5  /tmp/gmagick.tar.gz" | sha256sum -c -; \
	tar -xzf /tmp/gmagick.tar.gz -C /tmp/gmagick --strip-components=1; \
	( cd /tmp/gmagick && phpize && ./configure && make -j"$(nproc)" && make install ); \
	rm -rf /tmp/gmagick /tmp/gmagick.tar.gz; \
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
RUN curl -fsSLo /usr/local/bin/wp "https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar" \
		&& chmod +x /usr/local/bin/wp

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

# Fail the build on a PHP startup warning or error, a broken php-fpm config, wp or composer, or a missing module.
# The list is the previous image's full `php -m`, so it also catches a module dropped from PHP itself.
RUN set -eu; \
	out="$(php -v 2>&1 && php -m 2>&1)"; \
	if printf '%s\n' "$out" | grep -qiE 'warning|error|notice|unable to'; then \
		echo "Build check failed: PHP printed these startup warnings or errors:" >&2; \
		printf '%s\n' "$out" | grep -iE 'warning|error|notice|unable to' >&2; \
		exit 1; \
	fi; \
	php-fpm -t; \
	wp --allow-root --version; \
	COMPOSER_ALLOW_SUPERUSER=1 composer --version; \
	modules="$(php -m | tr '[:upper:] ' '[:lower:]_')"; \
	for m in apcu bcmath calendar core ctype curl date dom exif fileinfo filter gd gmagick gmp hash iconv imagick imap intl json libxml mbstring mcrypt memcached mysqli mysqlnd newrelic openssl pcntl pcre pdo pdo_mysql pdo_sqlite phar posix random readline redis reflection session shmop simplexml soap sockets sodium spl sqlite3 standard sysvsem sysvshm timezonedb tokenizer xml xmlreader xmlwriter zend_opcache zip zlib; do \
		printf '%s\n' "$modules" | grep -qx "$m" || { echo "Build check failed: PHP module $m is missing" >&2; exit 1; }; \
	done; \
	# The checks above leave root-owned logs that www-data couldn't write at runtime; don't ship them
	rm -f /var/log/php/access.log /var/log/php/error.log /var/log/newrelic/php_agent.log

WORKDIR /var/www/htdocs
RUN usermod -s /bin/bash www-data
USER www-data

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm"]
