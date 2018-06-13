FROM debian:stretch

MAINTAINER Tomas Sapak <tom.sapak@gmail.com>

ENV OPENLDAP_VERSION 2.4.44

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        slapd=${OPENLDAP_VERSION}* ldap-utils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mv /etc/ldap /etc/ldap.dist

COPY config/ /tmp

COPY entrypoint.sh /entrypoint.sh

EXPOSE 389

VOLUME ["/etc/ldap", "/var/lib/ldap"]

ENTRYPOINT ["/entrypoint.sh"]

CMD ["slapd", "-d", "32768", "-u", "openldap", "-g", "openldap"]