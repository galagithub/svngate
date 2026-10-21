FROM alpine:3.24

ARG WEBSVN_VERSION=2.9.0

ENV WEBSVN_VERSION="${WEBSVN_VERSION}"

# ------------------------------------------------------------
# Packages
# ------------------------------------------------------------

RUN apk add --no-cache \
    apache2 \
    apache2-utils \
    apache2-ssl \
    apache2-webdav \
    mod_dav_svn \
    subversion \
    subversion-tools \
    php84 \
    php84-cli \
    php84-apache2 \
    php84-ctype \
    php84-curl \
    php84-dom \
    php84-fileinfo \
    php84-gd \
    php84-iconv \
    php84-mbstring \
    php84-openssl \
    php84-session \
    php84-simplexml \
    php84-xml \
    php84-zip \
    curl \
    tar \
    openssl

# ------------------------------------------------------------
# Directories
# ------------------------------------------------------------

RUN mkdir -p \
    /var/svn \
    /var/www/websvn \
    /etc/apache2/svn-auth \
    /etc/apache2/certs \
    /run/apache2

# ------------------------------------------------------------
# WebSVN
# ------------------------------------------------------------

RUN curl -fsSL \
        "https://github.com/websvnphp/websvn/archive/refs/tags/${WEBSVN_VERSION}.tar.gz" \
        -o /tmp/websvn.tar.gz \
    && tar -xzf /tmp/websvn.tar.gz -C /tmp \
    && cp -a \
        "/tmp/websvn-${WEBSVN_VERSION}/." \
        /var/www/websvn/ \
    && rm -rf \
        /tmp/websvn.tar.gz \
        "/tmp/websvn-${WEBSVN_VERSION}"

# ------------------------------------------------------------
# Apache
# ------------------------------------------------------------

COPY apache.conf /etc/apache2/conf.d/apache-svn.conf

# ------------------------------------------------------------
# Entrypoint
# ------------------------------------------------------------

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY daemon-start.sh /usr/local/bin/daemon-start.sh

RUN chmod +x /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/daemon-start.sh

VOLUME ["/var/svn"]

EXPOSE 80
EXPOSE 3690

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
