FROM php:cli-stretch

## Install dependencies
RUN set -ex; \
	\
	deps=' \
	less \
	mysql-client \
	ca-certificates \
	gnupg2 \
	dirmngr \
	'; \
	apt-get update \
	&& apt-get install -y --no-install-recommends $deps sudo


## Install gosu
ENV GOSU_VERSION 1.7
RUN curl -o /usr/local/bin/gosu -L "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
	&& curl -o /usr/local/bin/gosu.asc -L "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
	&& gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
	&& rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc \
	&& chmod +x /usr/local/bin/gosu \
	&& gosu nobody true \
	&& rm -rf /var/lib/apt/lists/*;

# Install Docker-client
ENV VERSION "17.03.1-ce"
RUN curl -o /tmp/docker-$VERSION.tgz -L https://download.docker.com/linux/static/stable/x86_64/docker-$VERSION.tgz \
	&& tar -xz -C /tmp -f /tmp/docker-$VERSION.tgz \
	&& mv /tmp/docker/docker /usr/bin \
	&& rm -rf /tmp/docker-$VERSION /tmp/docker \
	&& apt-get purge -y --auto-remove $deps

# Install Docker-compose
ENV COMPOSE_VERSION 1.19.0
RUN curl -o /usr/local/bin/docker-compose -L \
	"https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-Linux-x86_64" \
	&& chmod +x /usr/local/bin/docker-compose && docker-php-ext-install pcntl

# Install EasyEngine v4 phar
RUN curl https://raw.githubusercontent.com/EasyEngine/easyengine-builds/master/phar/easyengine.phar -o /usr/local/bin/ee4 \
	&& chmod +x /usr/local/bin/ee4

COPY entrypoint.sh /app/entrypoint.sh

VOLUME ["/app/ee/Sites", "/app/ee/.ee4"]
ENTRYPOINT ["/app/entrypoint.sh"]