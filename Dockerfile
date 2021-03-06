FROM golang:1.9-alpine as builder

RUN apk add --no-cache git

ARG SERVER_REPO="github.com/mholt/caddy"
ARG BUILDS_REPO="github.com/caddyserver/builds"
ARG VERSION="0.10.10"

# Get Caddy source code and dependencies
RUN go get -u ${SERVER_REPO} \
    && go get -u ${BUILDS_REPO}

# List of desired plugins
# Empty or repos separated with spaces: "user/repo anotheruser/anotherrepo"
# Plugins list:
# - casbin/caddy-authz: middleware that blocks or allows requests based on ACP.
# - nicolasazrak/caddy-cache: caching middleware.
# - captncraig/cors: Cross Origin Resource Sharing middleware.
# - epicagency/caddy-expires: add expires headers to certain paths.
# - hacdias/filemanager/caddy/filemanager: provides a file managing interface.
# - abiosoft/caddy-git: makes it possible to deploy with a simple git push.
# - hacdias/filemanager/caddy/hugo: web interface to manage the Hugo websites.
# - SchumacherFM/mailout: SMTP client email middleware with PGP encryption.
# - hacdias/caddy-minify: plugin that provides file minification.
# - miekg/caddy-prometheus: Prometheus metrics middleware.
# - Xumeiquer/nobots: protect your website against web crawlers and bots.
# - tarent/loginsrv: login directive. Play together with the http.jwt middleware
# - BTBurke/caddy-jwt: JWT middleware.
ARG PLUGINS

RUN set -ex \
    && if [[ ! -z "${PLUGINS}" ]]; then \
       { \
            echo 'package caddymain'; \
            echo 'import ('; \
          } > $GOPATH/src/${SERVER_REPO}/caddy/caddymain/plugins.go \
      && for i in ${PLUGINS}; \
          do echo "_ \"github.com/${i}\"" >> $GOPATH/src/${SERVER_REPO}/caddy/caddymain/plugins.go; done \
      && echo ")" >> $GOPATH/src/${SERVER_REPO}/caddy/caddymain/plugins.go \
      && for i in ${PLUGINS}; \
          do go get -u github.com/${i}; \
          done \
      fi

WORKDIR $GOPATH/src/${SERVER_REPO}/caddy/

RUN set -ex \
    && if [[ "${VERSION}" != "git" ]]; then \
        git checkout tags/"v${VERSION}"; \
      fi

# Build the source
RUN go run build.go -goos=linux -goarch=amd64 \
    && mv caddy /usr/local/bin

FROM tscangussu/tini:0.16.1-1.alpine

LABEL Maintainer="Thiago Cangussu <thiago.cangussu@gmail.com>" \
      Description="Caddy Server based on Alpine Linux." \
      Version="v0.10.10" \
      Revision="1"

ARG CADDYBIN="/usr/local/bin/caddy"

COPY --from=builder ${CADDYBIN} ${CADDYBIN}

# Give Caddy permission to bind to port 80 and 443 without being root
RUN apk add --no-cache libcap && setcap cap_net_bind_service=+ep ${CADDYBIN}

ENV CADDYROOT /usr/share/local/caddy/

COPY html ${CADDYROOT}

# Ensure www-data user exists and set proper permissions
RUN set -x \
	&& addgroup -g 82 -S www-data \
  && adduser -u 82 -D -S -G www-data www-data \
  && chown -R www-data:www-data ${CADDYROOT} \
  && chmod -R 755 ${CADDYROOT}

# Path to store SSL certificates. It needs a volume to persist.
ENV CADDYPATH /etc/caddY

VOLUME ${CADDYPATH}

WORKDIR ${CADDYROOT}

COPY docker-caddy-entrypoint /usr/local/bin

# Expose ports 80 & 443 for production, 2015 for development (Caddy's default).
EXPOSE 80 443 2015

# Run Caddy as non-root user.
USER www-data

# Run docker-caddy-entrypoint after tini has been started as PID 1.
ENTRYPOINT ["tini", "--", "docker-caddy-entrypoint"]

CMD ["caddy"]
