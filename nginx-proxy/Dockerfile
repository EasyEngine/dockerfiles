FROM jwilder/nginx-proxy:1.11.6
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="nginx-proxy"

COPY nginx.tmpl /app/
COPY nginx.conf /etc/nginx/nginx.conf
COPY version.conf /version.conf
COPY default.html /etc/nginx/html/default.html

# nginx-proxy 1.11.6 ships nginx 1.31.3; take the nginx.org packages with the 1.31.7 security fixes
# (same set as the official nginx image) until an upstream release does. Drop this block then.
ENV NGINX_VERSION=1.31.8 \
    NJS_VERSION=1.0.2

# The upstream image isn't rebuilt between nginx-proxy releases, so apply pending Debian updates here.
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install --no-install-recommends apache2-utils -y \
    && echo "deb [signed-by=/etc/apt/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/mainline/debian/ trixie nginx" > /etc/apt/sources.list.d/nginx.list \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
        nginx=${NGINX_VERSION}-${PKG_RELEASE} \
        nginx-module-xslt=${NGINX_VERSION}-${DYNPKG_RELEASE} \
        nginx-module-geoip=${NGINX_VERSION}-${DYNPKG_RELEASE} \
        nginx-module-image-filter=${NGINX_VERSION}-${DYNPKG_RELEASE} \
        nginx-module-njs=${NGINX_VERSION}+${NJS_VERSION}-${NJS_RELEASE} \
        nginx-module-acme=${NGINX_VERSION}+${ACME_VERSION}-${PKG_RELEASE} \
    && rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/nginx.list

RUN chmod +x /app/docker-entrypoint.sh
RUN rm -rf /var/log/nginx/access.log /var/log/nginx/error.log && touch /var/log/nginx/access.log /var/log/nginx/error.log
