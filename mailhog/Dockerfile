# mailhog/mailhog is amd64-only and unmaintained, so build the same v1.0.1 from source for every arch.
FROM golang:1.27.3-alpine3.24 AS build
ARG MAILHOG_VERSION=v1.0.1
RUN apk add --no-cache git \
 && git clone --depth 1 --branch "${MAILHOG_VERSION}" https://github.com/mailhog/MailHog.git /go/src/github.com/mailhog/MailHog
WORKDIR /go/src/github.com/mailhog/MailHog
# v1.0.1 predates Go modules; build from its vendor/ tree in GOPATH mode.
RUN CGO_ENABLED=0 GO111MODULE=off go build -trimpath -ldflags '-s -w' -o /MailHog .

FROM alpine:3.24.3
LABEL org.label-schema.schema-version="1.0.0"
LABEL org.label-schema.vendor="EasyEngine"
LABEL org.label-schema.name="mailhog"

# Same user, workdir, entrypoint and ports as mailhog/mailhog:v1.0.1.
RUN adduser -D -u 1000 mailhog
COPY --from=build /MailHog /usr/local/bin/MailHog
USER mailhog
WORKDIR /home/mailhog
ENTRYPOINT ["MailHog"]
EXPOSE 1025 8025
