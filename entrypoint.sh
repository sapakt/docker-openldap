#!/bin/bash

# When not limiting the open file descritors limit, the memory consumption of
# slapd is absurdly high. See https://github.com/docker/docker/issues/8231
ulimit -n 8192


set -e

LDAP_FORCE_RECONFIGURE="${LDAP_FORCE_RECONFIGURE:-false}"
LDAP_TLS="${LDAP_TLS:-false}"
LDAP_REPLICATION="${LDAP_REPLICATION:-false}"

# force OpenLDAP to listen on all interfaces
ETC_HOSTS=$(cat /etc/hosts | sed "/$HOSTNAME/d")
echo "0.0.0.0 $HOSTNAME" > /etc/hosts
echo "$ETC_HOSTS" >> /etc/hosts

if [[ ! -d /etc/ldap/slapd.d || "$LDAP_FORCE_RECONFIGURE" == "true" ]]; then

    echo "Info: Entering reconfigure stage"

    if [[ -z "$LDAP_PASSWORD" ]]; then
        echo -n >&2 "Error: Container not configured and LDAP_PASSWORD not set. "
        echo >&2 "Did you forget to add -e LDAP_PASSWORD=... ?"
        exit 1
    fi

    if [[ -z "$LDAP_DOMAIN" ]]; then
        echo -n >&2 "Error: Container not configured and LDAP_DOMAIN not set. "
        echo >&2 "Did you forget to add -e LDAP_DOMAIN=... ?"
        exit 1
    fi

    LDAP_ORGANIZATION="${LDAP_ORGANIZATION:-${LDAP_DOMAIN}}"

    cp -r /etc/ldap.dist/* /etc/ldap

    cat <<-EOF | debconf-set-selections
        slapd slapd/no_configuration boolean false
        slapd slapd/password1 password $LDAP_PASSWORD
        slapd slapd/password2 password $LDAP_PASSWORD
        slapd shared/organization string $LDAP_ORGANIZATION
        slapd slapd/domain string $LDAP_DOMAIN
        slapd slapd/backend select MDB
        slapd slapd/allow_ldap_v2 boolean false
        slapd slapd/purge_database boolean false
        slapd slapd/move_old_database boolean true
EOF

    dpkg-reconfigure -f noninteractive slapd >/dev/null 2>&1

    dc_string=""

    IFS="."; declare -a dc_parts=($LDAP_DOMAIN); unset IFS

    for dc_part in "${dc_parts[@]}"; do
        dc_string="$dc_string,dc=$dc_part"
    done

    base_string="BASE ${dc_string:1}"

    sed -i "s/^#BASE.*/${base_string}/g" /etc/ldap/ldap.conf

    if [[ -n "$LDAP_CONFIG_PASSWORD" ]]; then
        password_hash=`slappasswd -s "${LDAP_CONFIG_PASSWORD}"`

        sed_safe_password_hash=${password_hash//\//\\\/}

        slapcat -n0 -F /etc/ldap/slapd.d -l /tmp/config.ldif
        sed -i "s/\(olcRootDN: cn=admin,cn=config\)/\1\nolcRootPW: ${sed_safe_password_hash}/g" /tmp/config.ldif
        rm -rf /etc/ldap/slapd.d/*
        slapadd -n0 -F /etc/ldap/slapd.d -l /tmp/config.ldif
        rm /tmp/config.ldif
    fi

    if [[ "$LDAP_TLS" == "true" || "$LDAP_REPLICATION" == "true" ]]; then
        chown -R openldap:openldap /etc/ldap/slapd.d/ /var/lib/ldap/ /var/run/slapd/

        slapd -d 256 -u openldap -g openldap -h "ldap:/// ldap://$HOSTNAME ldapi:///" 2>&1 &

        echo "Info: Waiting for OpenLDAP to start..."
        while [ ! -e /run/slapd/slapd.pid ]; do sleep 0.1; done
    fi

    if [[ "$LDAP_TLS" == "true" ]]; then
        if [[ -z "$LDAP_TLS_PATH" || -z "$LDAP_TLS_CACERT" || -z "$LDAP_TLS_CERT" || -z "$LDAP_TLS_KEY" ]]; then
            echo -n >&2 "Error: LDAP_TLS set and LDAP_TLS* not set. "
            echo >&2 "Did you forget to add -e LDAP_TLS*=... ?"
            exit 1
        fi
        chown -R openldap:openldap $LDAP_TLS_PATH
        sed -i "s|{{ LDAP_TLS_CACERT }}|${LDAP_TLS_PATH}/${LDAP_TLS_CACERT}|g" /tmp/ssl.ldif
        sed -i "s|{{ LDAP_TLS_CERT }}|${LDAP_TLS_PATH}/${LDAP_TLS_CERT}|g" /tmp/ssl.ldif
        sed -i "s|{{ LDAP_TLS_KEY }}|${LDAP_TLS_PATH}/${LDAP_TLS_KEY}|g" /tmp/ssl.ldif
        ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f /tmp/ssl.ldif
        ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f /tmp/sslonly.ldif
    fi

    if [[ "$LDAP_REPLICATION" == "true" ]]; then
        if [[ "$LDAP_TLS" == "true" ]]; then
            LDAP_REPLICATION_CONFIG_SYNCPROV='binddn="cn=admin,cn=config" bindmethod=simple credentials="$LDAP_CONFIG_PASSWORD" searchbase="cn=config" type=refreshAndPersist retry="60 +" timeout=1 starttls=critical tls_reqcert=demand'
            LDAP_REPLICATION_DB_SYNCPROV='binddn="cn=admin,$LDAP_BASE_DN" bindmethod=simple credentials="$LDAP_PASSWORD" searchbase="$LDAP_BASE_DN" type=refreshAndPersist interval=00:00:00:10 retry="60 +" timeout=1 starttls=critical tls_reqcert=demand'
        else
          LDAP_REPLICATION_CONFIG_SYNCPROV='binddn="cn=admin,cn=config" bindmethod=simple credentials="$LDAP_CONFIG_PASSWORD" searchbase="cn=config" type=refreshAndPersist retry="60 +" timeout=1'
          LDAP_REPLICATION_DB_SYNCPROV='binddn="cn=admin,$LDAP_BASE_DN" bindmethod=simple credentials="$LDAP_PASSWORD" searchbase="$LDAP_BASE_DN" type=refreshAndPersist interval=00:00:00:10 retry="60 +" timeout=1'
        fi
        i=1
        for host in $(echo $LDAP_REPLICATION_HOSTS | sed "s/,/ /g")
        do
            sed -i "s|{{ LDAP_REPLICATION_HOSTS }}|olcServerID: $i ${host}\n{{ LDAP_REPLICATION_HOSTS }}|g" /tmp/replication.ldif
            sed -i "s|{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}|olcSyncRepl: rid=00$i provider=${host} ${LDAP_REPLICATION_CONFIG_SYNCPROV}\n{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}|g" /tmp/replication.ldif
            sed -i "s|{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}|olcSyncRepl: rid=10$i provider=${host} ${LDAP_REPLICATION_DB_SYNCPROV}\n{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}|g" /tmp/replication.ldif

            ((i++))
        done

        sed -i "s|\$LDAP_BASE_DN|$LDAP_BASE_DN|g" /tmp/replication.ldif
        sed -i "s|\$LDAP_PASSWORD|$LDAP_PASSWORD|g" /tmp/replication.ldif
        sed -i "s|\$LDAP_CONFIG_PASSWORD|$LDAP_CONFIG_PASSWORD|g" /tmp/replication.ldif

        sed -i "/{{ LDAP_REPLICATION_HOSTS }}/d" /tmp/replication.ldif
        sed -i "/{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}/d" /tmp/replication.ldif
        sed -i "/{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}/d" /tmp/replication.ldif

        sed -i "s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g" /tmp/replication.ldif
        ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f /tmp/replication.ldif
    fi

    if [[ "$LDAP_TLS" == "true" || "$LDAP_REPLICATION" == "true" ]]; then
        killall -s SIGHUP slapd

        echo "Info: Waiting for OpenLDAP to shutdown..."
        while [ -e /run/slapd/slapd.pid ]; do sleep 0.1; done
    fi

else
    slapd_configs_in_env=`env | grep 'SLAPD_'`

    if [ -n "${slapd_configs_in_env:+x}" ]; then
        echo "Info: Container already configured, therefore ignoring SLAPD_xxx environment variables and preseed files"
    fi
fi

chown -R openldap:openldap /etc/ldap/slapd.d/ /var/lib/ldap/ /var/run/slapd/

exec "$@"
