OpenLDAP
========
This image is based on [dinkel/openldap](https://hub.docker.com/r/dinkel/openldap/)
and [osixia/openldap](https://hub.docker.com/r/osixia/openldap/). It aims to be
as simple as possible, but supports TLS and replication.

Configuration
-------------

There are several configuration options via environment variables.
Required:
* `LDAP_DOMAIN` - sets the DC (Domain component) parts. E.g. if one sets
it to `ldap.example.org`, the generated base DC parts would be `...,dc=ldap,dc=example,dc=org`.
* `LDAP_PASSWORD` - sets the password for the `admin` user.
* `HOSTNAME` - host fqdn

Optional:
* `LDAP_ORGANIZATION` - (defaults to $LDAP_DOMAIN) - represents the human readable
company name (e.g. `Example Inc.`).
* `LDAP_CONFIG_PASSWORD` - allows password protected access to the `dn=config`
branch. This helps to reconfigure the server without interruption (read the
[official documentation](http://www.openldap.org/doc/admin24/guide.html#Configuring%20slapd)).
* `LDAP_FORCE_RECONFIGURE` - (defaults to false) - used if one needs to reconfigure
the `slapd` service after the image has been initialized.  Set this value to `true`
to reconfigure the image.
* `LDAP_REPLICATION` - (defaults to false) - setups replication
* `LDAP_TLS` - (defaults to false) - setups TLS

Required for replication:
* `LDAP_REPLICATION_HOSTS` - list of replicated hosts (e.g "ldap://ldap1.example.org, ldap://ldap2.example.org")

Required for TLS (https://help.ubuntu.com/lts/serverguide/openldap-server.html.en#openldap-tls):
* `LDAP_TLS_PATH` - path to folder with certificates/keys (ideally mounted via volume)
* `LDAP_TLS_CACERT` - CA certificate name
* `LDAP_TLS_CERT` - host certificate name
* `LDAP_TLS_KEY` - host key name


Volumes
----------------

It is suggested to mount two (three in case of replication) volumes for data persistence:
* `/var/lib/ldap` - LDAP database
* `/etc/ldap`- LDAP configuration

* `/etc/ssl` - directory with TLS certificates and key
