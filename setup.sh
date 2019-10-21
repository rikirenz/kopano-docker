#!/bin/bash

set -e

fqdn_to_dn() {
	printf 'dc=%s' "$1" | sed -E 's/\./,dc=/g'
}

random_string() {
	LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c32
}

LANG_OPTIONS=("de-at" "de-ch" "de-de" "en" "en-gb" "es" "fr" "it" "nl" "pl-pl")
PLUGIN_OPTIONS=("contactfax" "desktopnotifications" "filepreviewer" "files" "filesbackend-smb" "filesbackend-owncloud" "folderwidgets" "gmaps" "intranet" "mattermost" "mdm" "pimfolder" "quickitems" "smime" "titlecounter" "webappmanual" "zdeveloper")

lang_menu() {
	echo "Available options:"
	for i in "${!LANG_OPTIONS[@]}"; do
		printf "%3d%s) %s\n" $((i+1)) "${lang_choices[i]:- }" "${LANG_OPTIONS[i]}"
	done
	[[ "$msg" ]] && echo "$msg"; :
}

plugin_menu() {
	echo "Available options:"
	for i in "${!PLUGIN_OPTIONS[@]}"; do
		printf "%3d%s) %s\n" $((i+1)) "${plugin_choices[i]:- }" "${PLUGIN_OPTIONS[i]}"
	done
	[[ "$msg" ]] && echo "$msg"; :
}

docker_tag_search() {
	image="$1"
	results=$(reg tags "$image" 2> /dev/null)
	echo "$results" | xargs -n1 | sort --version-sort -ru | xargs
}

echo "Creating individual env files for containers (if they do not exist already)"
for dockerenv in ldap password-self-service mail db kopano_ssl kopano_server kopano_webapp kopano_zpush kopano_grapi kopano_kapi kopano_dagent kopano_spooler kopano_gateway kopano_ical kopano_monitor kopano_scheduler kopano_search kopano_konnect kopano_kwmserver kopano_meet; do
	touch ./"$dockerenv".env
done

if [ ! -e ./.env ]; then
	PRINT_SETUP_SUCCESS=""

	echo "Creating an .env file for you"

	# if the optional https://github.com/genuinetools/reg is installed this will list available tags
	if command -v reg > /dev/null; then
		echo "Available tags in zokradonh/kopano_core/: $(docker_tag_search zokradonh/kopano_core)"
	fi
	value_default=latest
	read -r -p "Which tag do you want to use for Kopano Core components? [$value_default]: " new_value
	CORE_VERSION=${new_value:-$value_default}

	if command -v reg > /dev/null; then
		echo "Available tags in https://hub.docker.com/r/zokradonh/kopano_webapp/: $(docker_tag_search zokradonh/kopano_webapp)"
	fi
	value_default=latest
	read -r -p "Which tag do you want to use for Kopano WebApp? [$value_default]: " new_value
	WEBAPP_VERSION=${new_value:-$value_default}

	if command -v reg > /dev/null; then
		echo "Available tags in https://hub.docker.com/r/zokradonh/kopano_zpush/: $(docker_tag_search zokradonh/kopano_zpush)"
	fi
	value_default=latest
	read -r -p "Which tag do you want to use for Z-Push? [$value_default]: " new_value
	ZPUSH_VERSION=${new_value:-$value_default}

	if command -v reg > /dev/null; then
		echo "Available tags in https://hub.docker.com/r/zokradonh/kopano_konnect/: $(docker_tag_search zokradonh/kopano_konnect)"
	fi
	value_default=latest
	read -r -p "Which tag do you want to use for Kopano Konnect? [$value_default]: " new_value
	KONNECT_VERSION=${new_value:-$value_default}

	value_default=latest
	read -r -p "Which tag do you want to use for Kopano Kwmserver? [$value_default]: " new_value
	KWM_VERSION=${new_value:-$value_default}

	value_default=latest
	read -r -p "Which tag do you want to use for Kopano Meet? [$value_default]: " new_value
	MEET_VERSION=${new_value:-$value_default}

	value_default=latest
	read -r -p "Which tag do you want to use for Kopano kDAV? [$value_default]: " new_value
	KDAV_VERSION=${new_value:-$value_default}

	value_default="Kopano Demo"
	read -r -p "Name of the Organisation for LDAP [$value_default]: " new_value
	LDAP_ORGANISATION=${new_value:-$value_default}

	value_default="kopano.demo"
	read -r -p "FQDN to be used (for reverse proxy).
	Hint: use port 2015 in case port 443 is already in use on the system.
	[$value_default]: " new_value
	FQDN=${new_value:-$value_default}

	value_default="self_signed"
	read -r -p "Email address to use for Lets Encrypt.
	Use 'self_signed' as your email to create self signed certificates.
	Use 'off' if you want to run the service without tls encryption. Make sure to use an ssl-terminating reverse proxy in front in this case.
	[$value_default]: " new_value
	EMAIL=${new_value:-$value_default}

	# Let Kapi accept self signed certs if required
	if [ "$EMAIL" == "self_signed" ]; then
		INSECURE="yes"
	else
		INSECURE="no"
	fi

	LDAP_BASE_DN=$(fqdn_to_dn "${FQDN%:*}")
	value_default="$LDAP_BASE_DN"
	read -r -p "Name of the BASE DN for LDAP [$value_default]: " new_value
	LDAP_BASE_DN=${new_value:-$value_default}

	value_default="ldap://ldap:389"
	read -r -p "LDAP server to be used (defaults to the bundled OpenLDAP) [$value_default]: " new_value
	LDAP_SERVER=${new_value:-$value_default}

	if [ "$LDAP_SERVER" != "$value_default" ]; then
		# We don't need an admin password in case we don't use the bundled LDAP server
		LDAP_ADMIN_PASSWORD=""

		value_default="$LDAP_BASE_DN"
		read -r -p "LDAP search base [$value_default]: " new_value
		LDAP_SEARCH_BASE=${new_value:-$value_default}

		value_default="cn=readonly,$LDAP_BASE_DN"
		read -r -p "LDAP bind user (needs read permissions) [$value_default]: " new_value
		LDAP_BIND_DN=${new_value:-$value_default}

		value_default="kopano123"
		read -r -p "LDAP bind password to be used [$value_default]: " new_value
		LDAP_BIND_PW=${new_value:-$value_default}

		PRINT_SETUP_SUCCESS="$PRINT_SETUP_SUCCESS \n!! You have specified the LDAP server '${LDAP_SERVER}', don't forget to remove the bundled ldap and ldap-admin services in docker-compose.yml\n"
	else
		value_default="yes"
		read -r -p "Use bundled LDAP with demo users? yes/no [$value_default]: " new_value
		LDAP_CONTAINER_QUESTION=${new_value:-$value_default}

		if [ "${LDAP_CONTAINER_QUESTION}" == "yes" ]; then
			LDAP_CONTAINER="kopano_ldap_demo"
		else
			LDAP_CONTAINER="kopano_ldap"
		fi

		LDAP_ADMIN_PASSWORD=$(random_string)
		LDAP_SEARCH_BASE="$LDAP_BASE_DN"
		LDAP_BIND_DN="cn=readonly,$LDAP_BASE_DN"
		LDAP_BIND_PW=$(random_string)
	fi

	# TODO get locale from system
	value_default="en_US.UTF-8"
	read -r -p "Language to be used for new mailoboxes (needs to be available as a locale in the container) [$value_default]: " new_value
	MAILBOXLANG=${new_value:-$value_default}

	if [ -f /etc/timezone ]; then
		value_default=$(cat /etc/timezone)
	elif [ -f /etc/localtime ]; then
		value_default=$(readlink /etc/localtime|sed -n 's|^.*zoneinfo/||p')
	else
		value_default="Europe/Berlin"
	fi

	read -r -p "Timezone to be used [$value_default]: " new_value
	TZ=${new_value:-$value_default}

	value_default="postmaster@${FQDN%:*}"
	read -r -p "E-Mail Address displayed for the 'postmaster' [$value_default]: " new_value
	POSTMASTER_ADDRESS=${new_value:-$value_default}

	value_default="db"
	read -r -p "Name/Address of Database server (defaults to the bundled one) [$value_default]: " new_value
	MYSQL_HOST=${new_value:-$value_default}

	if [ "$MYSQL_HOST" != "$value_default" ]; then
		# We don't need an admin password in case we don't use the bundled DB server
		MYSQL_ROOT_PASSWORD=""

		value_default="kopanoDbUser"
		read -r -p "Username to connect to the database [$value_default]: " new_value
		MYSQL_USER=${new_value:-$value_default}

		value_default="kopanoDbPw"
		read -r -p "Password to connect to the database [$value_default]: " new_value
		MYSQL_PASSWORD=${new_value:-$value_default}

		value_default="kopano"
		read -r -p "Database to use for Kopano [$value_default]: " new_value
		MYSQL_DATABASE=${new_value:-$value_default}

		PRINT_SETUP_SUCCESS="$PRINT_SETUP_SUCCESS \n!! You have specified the DB server '${MYSQL_HOST}', don't forget to remove the bundled db service in docker-compose.yml\n"
	else
		MYSQL_USER="kopano"
		MYSQL_DATABASE="kopano"
		MYSQL_ROOT_PASSWORD=$(random_string)
		MYSQL_PASSWORD=$(random_string)
	fi

	ADDITIONAL_KOPANO_WEBAPP_PLUGINS=""

	prompt="Check language spell support (again to uncheck, ENTER when done): "
	while lang_menu && read -rp "$prompt" num && [[ "$num" ]]; do
		# shellcheck disable=SC2015
		[[ "$num" != *[![:digit:]]* ]] &&
		(( num > 0 && num <= ${#LANG_OPTIONS[@]} )) ||
		{ msg="Invalid option: $num"; continue; }
		((num--)); msg="${LANG_OPTIONS[num]} was ${lang_choices[num]:+un}checked"
		[[ "${lang_choices[num]}" ]] && lang_choices[num]="" || lang_choices[num]="+"
	done

	KOPANO_SPELL_PLUGIN=""
	KOPANO_SPELL_LANG_PLUGIN=""
	for i in "${!LANG_OPTIONS[@]}"; do
		[[ "${lang_choices[i]}" ]] && { KOPANO_SPELL_LANG_PLUGIN="${KOPANO_SPELL_LANG_PLUGIN} kopano-webapp-plugin-spell-${LANG_OPTIONS[i]}"; KOPANO_SPELL_PLUGIN="kopano-webapp-plugin-spell"; }
	done

	ADDITIONAL_KOPANO_WEBAPP_PLUGINS="${KOPANO_SPELL_PLUGIN}${KOPANO_SPELL_LANG_PLUGIN}"

	prompt="Check for additional plugins (again to uncheck, ENTER when done): "
	while plugin_menu && read -rp "$prompt" num && [[ "$num" ]]; do
		# shellcheck disable=SC2015
		[[ "$num" != *[![:digit:]]* ]] &&
		(( num > 0 && num <= ${#PLUGIN_OPTIONS[@]} )) ||
		{ msg="Invalid option: $num"; continue; }
		((num--)); msg="${PLUGIN_OPTIONS[num]} was ${plugin_choices[num]:+un}checked"
		[[ "${plugin_choices[num]}" ]] && plugin_choices[num]="" || plugin_choices[num]="+"
	done

	KOPANO_WEBAPP_PLUGIN=""
	for i in "${!PLUGIN_OPTIONS[@]}"; do
		[[ "${plugin_choices[i]}" ]] && { KOPANO_WEBAPP_PLUGIN="${KOPANO_WEBAPP_PLUGIN} kopano-webapp-plugin-${PLUGIN_OPTIONS[i]}"; }
	done

	ADDITIONAL_KOPANO_WEBAPP_PLUGINS="${ADDITIONAL_KOPANO_WEBAPP_PLUGINS}${KOPANO_WEBAPP_PLUGIN}"

	value_default="no"
	read -r -p "Integrate WhatsApp into DeskApp yes/no [$value_default]: " new_value
	WHATSAPPDESKAPP_BOOLEAN=${new_value:-$value_default}

	if [ "${WHATSAPPDESKAPP_BOOLEAN}" == "yes" ]; then
		ADDITIONAL_KOPANO_WEBAPP_PLUGINS="${ADDITIONAL_KOPANO_WEBAPP_PLUGINS} whatsapp4deskapp"
	fi

	echo "${PRINT_SETUP_SUCCESS}"

	cat <<EOF > "./.env"
# please consult https://github.com/zokradonh/kopano-docker
# for possible configuration values and their impact
CORE_VERSION=$CORE_VERSION
WEBAPP_VERSION=$WEBAPP_VERSION
ZPUSH_VERSION=$ZPUSH_VERSION
KONNECT_VERSION=$KONNECT_VERSION
KWM_VERSION=$KWM_VERSION
MEET_VERSION=$MEET_VERSION
KDAV_VERSION=$KDAV_VERSION

LDAP_CONTAINER=$LDAP_CONTAINER
LDAP_ORGANISATION="$LDAP_ORGANISATION"
LDAP_DOMAIN=${FQDN%:*}
LDAP_BASE_DN=$LDAP_BASE_DN
LDAP_SERVER=$LDAP_SERVER
LDAP_ADMIN_PASSWORD=$LDAP_ADMIN_PASSWORD
LDAP_READONLY_USER_PASSWORD=$LDAP_BIND_PW
LDAP_BIND_DN=$LDAP_BIND_DN
LDAP_BIND_PW=$LDAP_BIND_PW
LDAP_SEARCH_BASE=$LDAP_SEARCH_BASE

# LDAP query filters
LDAP_QUERY_FILTER_USER=(&(kopanoAccount=1)(mail=%s))
LDAP_QUERY_FILTER_GROUP=(&(objectclass=kopano-group)(mail=%s))
LDAP_QUERY_FILTER_ALIAS=(&(kopanoAccount=1)(kopanoAliases=%s))
LDAP_QUERY_FILTER_DOMAIN=(&(|(mail=*@%s)(kopanoAliases=*@%s)))
SASLAUTHD_LDAP_FILTER=(&(kopanoAccount=1)(uid=%s))

# LDAP user password self-service reset settings
SELF_SERVICE_SECRETEKEY=$(random_string)
SELF_SERVICE_PASSWORD_MIN_LENGTH=5
SELF_SERVICE_PASSWORD_MAX_LENGTH=0
SELF_SERVICE_PASSWORD_MIN_LOWERCASE=0
SELF_SERVICE_PASSWORD_MIN_UPPERCASE=0
SELF_SERVICE_PASSWORD_MIN_DIGIT=1
SELF_SERVICE_PASSWORD_MIN_SPECIAL=1

# switch the value of these two variables to use the activedirectory configuration
KCUNCOMMENT_LDAP_1=!include /usr/share/kopano/ldap.openldap.cfg
KCCOMMENT_LDAP_1=!include /usr/share/kopano/ldap.active-directory.cfg

MYSQL_HOST=$MYSQL_HOST
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_USER=$MYSQL_USER
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_DATABASE=$MYSQL_DATABASE

KCCONF_SERVER_SERVER_NAME=Kopano

POSTMASTER_ADDRESS=$POSTMASTER_ADDRESS
MAILBOXLANG=$MAILBOXLANG
TZ=$TZ

# Defines how Kopano can be accessed from the outside world
FQDN=$FQDN
FQDNCLEANED=${FQDN%:*}
DEFAULTREDIRECT=/webapp
EMAIL=$EMAIL
CADDY=2015
HTTP=80
HTTPS=443
LDAPPORT=389
SMTPPORT=25
SMTPSPORT=465
MSAPORT=587
IMAPPORT=143
ICALPORT=8080
KOPANOPORT=236
KOPANOSPORT=237

# Settings for test environments
INSECURE=$INSECURE

# Docker and docker-compose settings
# Docker Repository to push to/pull from
docker_repo=zokradonh
COMPOSE_PROJECT_NAME=kopano
COMPOSE_FILE=docker-compose.yml:docker-compose.ports.yml:grapi-explorer/grapi-explorer.yml

# Modify below to build a different version, than the kopano nightly release
#KOPANO_CORE_REPOSITORY_URL=https://serial:REPLACE-ME@download.kopano.io/supported/core:/final/Debian_9.0/
#KOPANO_MEET_REPOSITORY_URL=https://serial:REPLACE-ME@download.kopano.io/supported/meet:/final/Debian_9.0/
#KOPANO_WEBAPP_REPOSITORY_URL=https://serial:REPLACE-ME@download.kopano.io/supported/webapp:/final/Debian_9.0/
#KOPANO_WEBAPP_FILES_REPOSITORY_URL=https://serial:REPLACE-ME@download.kopano.io/supported/files:/final/Debian_9.0/
#KOPANO_WEBAPP_MDM_REPOSITORY_URL=https://serial:REPLACE-ME@download.kopano.io/supported/mdm:/final/Debian_9.0/
#KOPANO_WEBAPP_SMIME_REPOSITORY_URL=https://serial:REPLACE-ME@download.kopano.io/supported/smime:/final/Debian_9.0/
#KOPANO_ZPUSH_REPOSITORY_URL=http://repo.z-hub.io/z-push:/final/Debian_9.0/
#RELEASE_KEY_DOWNLOAD=1
#DOWNLOAD_COMMUNITY_PACKAGES=0

# Additional packages to install
ADDITIONAL_KOPANO_PACKAGES=""
ADDITIONAL_KOPANO_WEBAPP_PLUGINS="$ADDITIONAL_KOPANO_WEBAPP_PLUGINS"

EOF
else

	if ! grep -q COMPOSE_FILE ./.env; then
		echo "Adding COMPOSE_FILE setting to .env"
		echo "COMPOSE_FILE=docker-compose.yml:docker-compose.ports.yml" >> ./.env
	fi

	echo ".env already exists with initial configuration"
	echo "If you want to change the configuration, please edit .env directly"
	exit 1
fi
