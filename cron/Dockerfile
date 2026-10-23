FROM mcuadros/ofelia:0.3.22
LABEL org.label-schema.schema-version="1.0.0-rc1"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="cron"

# The upstream image isn't rebuilt between ofelia releases, so apply pending Alpine updates here.
RUN apk upgrade --no-cache
