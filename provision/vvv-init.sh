#!/usr/bin/env bash
# Provision WordPress Stable

set -eo pipefail

echo " * Custom site template provisioner ${VVV_SITE_NAME} - downloads and installs a copy of WP stable for testing, building client sites, etc"

# fetch the first host as the primary domain. If none is available, generate a default using the site name
DB_NAME=$(get_config_value 'db_name' "${VVV_SITE_NAME}")
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*]/}
DB_DUMP=$(get_config_value 'db_dump' 'database.sql')
DB_LINK=$(get_config_value 'db_link' '')
DB_PREFIX=$(get_config_value 'db_prefix' 'wp_')
DOMAIN=$(get_primary_host "${VVV_SITE_NAME}".test)

PUBLIC_DIR=$(get_config_value 'public_dir' "public_html")
SITE_TITLE=$(get_config_value 'site_title' "${DOMAIN}")
WP_LOCALE=$(get_config_value 'locale' 'en_US')
WP_TYPE=$(get_config_value 'wp_type' "single")
WP_VERSION=$(get_config_value 'wp_version' 'latest')

VVV_PATH_PROVISION="${VVV_PATH_TO_SITE}"

VVV_PATH_TO_SITE="${VVV_PATH_TO_SITE}/${DOMAIN}"

PUBLIC_DIR_PATH="${VVV_PATH_TO_SITE}"
if [ ! -z "${PUBLIC_DIR}" ]; then
  PUBLIC_DIR_PATH="${PUBLIC_DIR_PATH}/${PUBLIC_DIR}"
fi

# Make a database, if we don't already have one
setup_database() {
  echo -e " * Creating database '${DB_NAME}' (if it's not already there)"
  mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`"
  echo -e " * Granting the wp user priviledges to the '${DB_NAME}' database"
  mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO wp@localhost IDENTIFIED BY 'wp';"
  echo -e " * DB operations done."
}

setup_nginx_folders() {
  echo " * Setting up the logs subfolder for Nginx logs"
  noroot mkdir -p "${VVV_PATH_TO_SITE}/logs"
  noroot touch "${VVV_PATH_TO_SITE}/logs/error.log"
  noroot touch "${VVV_PATH_TO_SITE}/logs/access.log"
  #echo " * Creating the public folder at '${PUBLIC_DIR}' if it doesn't exist already"
  #noroot mkdir -p "${PUBLIC_DIR_PATH}"
}

setup_composer_auth() {
  echo " * Creating auth.json so composer can install premium plugins"
  echo "Enter your ACF Licence Key"
  read -e ACF_LICENCE_KEY
  echo "Enter your Admin Columns Pro Token"
  read -e AC_TOKEN
  sed -e "s|@@@SITE_URL@@@|https://${DOMAIN}|" -e "s|@@@ACF_LICENCE_KEY@@@|${ACF_LICENCE_KEY}|" -e "s|@@@AC_TOKEN@@@|${AC_TOKEN}|" "${PUBLIC_DIR_PATH}/auth-template.json" > "${PUBLIC_DIR_PATH}/auth.json"
  echo "Enter your Yoast SEO Token"
  read -e YOAST_SEO_TOKEN
  noroot composer config -g http-basic.my.yoast.com token "${YOAST_SEO_TOKEN}"
}

#install_plugins() {
#  WP_PLUGINS=$(get_config_value 'install_plugins' '')
#  if [ ! -z "${WP_PLUGINS}" ]; then
#    isurl='(https?|ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'
#    for plugin in ${WP_PLUGINS//- /$'\n'}; do
#      if [[ "${plugin}" =~ $isurl ]]; then
#        echo " ! Warning, a URL was found for this plugin, attempting install and activate with --force set for ${plugin}"
#        noroot wp plugin install "${plugin}" --activate --force
#      else
#        if noroot wp plugin is-installed "${plugin}"; then
#          echo " * The ${plugin} plugin is already installed."
#        else
#          echo " * Installing and activating plugin: '${plugin}'"
#          noroot wp plugin install "${plugin}" --activate
#        fi
#      fi
#    done
#  fi
#}

install_plugin() {
    plugin=$1
    if noroot wp plugin is-installed "${plugin}" --path=html/wp --skip-plugins --skip-themes; then
      echo " * The ${plugin} plugin is already installed."
    else
      echo " * Installing plugin: '${plugin}'"
      noroot wp plugin install "${plugin}" --path=html/wp --skip-plugins --skip-themes
    fi
}

install_plugins() {
  cd "${VVV_PATH_TO_SITE}"
  echo " * Installing and activating zipped premium plugins"
  PREMIUM_PLUGINS=()
  ZIPPED_PREMIUM_PLUGINS=($( ls premium-plugins )) #Add () to convert output to array
  for plugin in "${ZIPPED_PREMIUM_PLUGINS[@]}"; do
    #store in array for later
    PREMIUM_PLUGINS+=("${plugin%.*}")
    echo " * Installing the ${plugin%.*} plugin"
    noroot wp plugin install premium-plugins/"${plugin}" --force --path=html/wp --skip-plugins --skip-themes
  done
  echo " * Get Plugins List"
  PLUGINS_FILE=plugins.txt
  if test -f "$PLUGINS_FILE"; then
    readarray -t WP_PLUGINS < "$PLUGINS_FILE"
    #echo "${WP_PLUGINS[@]}"
	if [ ! -z "${WP_PLUGINS[*]}" ]; then
		echo " * Installing Plugins..."
    for plugin in "${WP_PLUGINS[@]}"; do
      install_plugin "${plugin}"
    done
    COMPOSER_PLUGINS_FILE=composer-plugins.txt
    if test -f "$COMPOSER_PLUGINS_FILE"; then
        readarray -t COMPOSER_PLUGINS < "$COMPOSER_PLUGINS_FILE"
    else
        COMPOSER_PLUGINS=()
    fi
    echo " * Activating Composer Plugins..."
    for plugin in "${COMPOSER_PLUGINS[@]}"; do
      install_plugin "${plugin}"
    done
    echo " * Updating plugins if necessary"
    noroot wp plugin update $(noroot wp plugin list --update=none --status=active --field=name --path=html/wp --skip-plugins --skip-themes) --path=html/wp --skip-plugins --skip-themes
	else
		echo " * No plugins to install"
	fi
  else
    echo " ! Warning: No plugins.txt found"
  fi
  cd "${PUBLIC_DIR_PATH}"
}


install_themes() {
  WP_THEMES=$(get_config_value 'install_themes' '')
  if [ ! -z "${WP_THEMES}" ]; then
      isurl='(https?|ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'
      for theme in ${WP_THEMES//- /$'\n'}; do
        if [[ "${theme}" =~ $isurl ]]; then
          echo " ! Warning, a URL was found for this theme, attempting install of ${theme} with --force set"
          noroot wp theme install --force "${theme}"
        else
          if noroot wp theme is-installed "${theme}"; then
            echo " * The ${theme} theme is already installed."
          else
            echo " * Installing theme: '${theme}'"
            noroot wp theme install "${theme}"
          fi
        fi
      done
  fi
}

copy_nginx_configs() {
  echo " * Copying the sites Nginx config template"
  if [ -f "${VVV_PATH_PROVISION}/provision/vvv-nginx-custom.conf" ]; then
    echo " * A vvv-nginx-custom.conf file was found"
    noroot cp -f "${VVV_PATH_PROVISION}/provision/vvv-nginx-custom.conf" "${VVV_PATH_PROVISION}/provision/vvv-nginx.conf"
  else
    echo " * Using the default vvv-nginx-default.conf, to customize, create a vvv-nginx-custom.conf"
    noroot cp -f "${VVV_PATH_PROVISION}/provision/vvv-nginx-default.conf" "${VVV_PATH_PROVISION}/provision/vvv-nginx.conf"
  fi
  
  echo " * Applying public dir setting to Nginx config"
  noroot sed -i "s#{vvv_public_dir}#/${PUBLIC_DIR}#" "${VVV_PATH_PROVISION}/provision/vvv-nginx.conf"
  noroot sed -i "s#{vvv_path_to_site}#${VVV_PATH_TO_SITE}#" "${VVV_PATH_PROVISION}/provision/vvv-nginx.conf"

  if [ ! -z "$LIVE_URL" ]; then
    echo " * Adding support for Live URL redirects to NGINX of the website's media"
    # replace potential protocols, and remove trailing slashes
    LIVE_URL=$(echo "${LIVE_URL}" | sed 's|https://||' | sed 's|http://||'  | sed 's:/*$::')

    redirect_config=$((cat <<END_HEREDOC
	if (!-e \$request_filename) {
	  rewrite ^/[_0-9a-zA-Z-]+(/content/uploads/.*) \$1;
	}
	if (!-e \$request_filename) {
	  rewrite ^/content/uploads/(.*)\$ \$scheme://${LIVE_URL}/content/uploads/\$1 redirect;
	}
	END_HEREDOC

    ) |
    # pipe and escape new lines of the HEREDOC for usage in sed
    sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n\\1/g'
    )

    noroot sed -i -e "s|\(.*\){{LIVE_URL}}|\1${redirect_config}|" "${VVV_PATH_PROVISION}/provision/vvv-nginx.conf"
  else
    noroot sed -i "s#{{LIVE_URL}}##" "${VVV_PATH_PROVISION}/provision/vvv-nginx.conf"
  fi
}

setup_wp_config_constants(){
  set +e
  noroot shyaml get-values-0 -q "sites.${VVV_SITE_NAME}.custom.wpconfig_constants" < "${VVV_CONFIG}" |
  while IFS='' read -r -d '' key &&
        IFS='' read -r -d '' value; do
      lower_value=$(echo "${value}" | awk '{print tolower($0)}')
      echo " * Adding constant '${key}' with value '${value}' to wp-config.php"
      if [ "${lower_value}" == "true" ] || [ "${lower_value}" == "false" ] || [[ "${lower_value}" =~ ^[+-]?[0-9]*$ ]] || [[ "${lower_value}" =~ ^[+-]?[0-9]+\.?[0-9]*$ ]]; then
        noroot wp config set "${key}" "${value}" --raw
      else
        noroot wp config set "${key}" "${value}"
      fi
  done
  set -e
}

restore_db_backup() {
  echo " * Found a database backup at ${1}. Restoring the site"
#  noroot wp config set DB_USER "wp"
#  noroot wp config set DB_PASSWORD "wp"
#  noroot wp config set DB_HOST "localhost"
#  noroot wp config set DB_NAME "${DB_NAME}"
#  noroot wp config set table_prefix "${DB_PREFIX}"
   noroot wp db import "${1}"
  echo " * Installed database backup"
}

download_wordpress() {
  # Install and configure the latest stable version of WordPress
  echo " * Downloading WordPress version '${1}' locale: '${2}'"
  noroot wp core download --locale="${2}" --version="${1}"
}

initial_wpconfig() {
  echo " * Setting up wp-config.php"
  noroot wp config create --dbname="${DB_NAME}" --dbprefix="${DB_PREFIX}" --dbuser=wp --dbpass=wp
  noroot wp config set WP_DEBUG true --raw
  noroot wp config set SCRIPT_DEBUG true --raw
}

maybe_import_test_content() {
  INSTALL_TEST_CONTENT=$(get_config_value 'install_test_content' "")
  if [ ! -z "${INSTALL_TEST_CONTENT}" ]; then
    echo " * Downloading test content from github.com/poststatus/wptest/master/wptest.xml"
    noroot curl -s https://raw.githubusercontent.com/poststatus/wptest/master/wptest.xml > /tmp/import.xml
    echo " * Installing the wordpress-importer"
    noroot wp plugin install wordpress-importer
    echo " * Activating the wordpress-importer"
    noroot wp plugin activate wordpress-importer
    echo " * Importing test data"
    noroot wp import /tmp/import.xml --authors=create
    echo " * Cleaning up import.xml"
    rm /tmp/import.xml
    echo " * Test content installed"
  fi
}

install_wp() {
  echo " * Installing WordPress"
  ADMIN_USER=$(get_config_value 'admin_user' "admin")
  ADMIN_PASSWORD=$(get_config_value 'admin_password' "password")
  ADMIN_EMAIL=$(get_config_value 'admin_email' "admin@local.test")

  echo " * Installing using wp core install --url=\"${DOMAIN}\" --title=\"${SITE_TITLE}\" --admin_name=\"${ADMIN_USER}\" --admin_email=\"${ADMIN_EMAIL}\" --admin_password=\"${ADMIN_PASSWORD}\""
  noroot wp core install --url="${DOMAIN}" --title="${SITE_TITLE}" --admin_name="${ADMIN_USER}" --admin_email="${ADMIN_EMAIL}" --admin_password="${ADMIN_PASSWORD}"
  echo " * WordPress was installed, with the username '${ADMIN_USER}', and the password '${ADMIN_PASSWORD}' at '${ADMIN_EMAIL}'"

  if [ "${WP_TYPE}" = "subdomain" ]; then
    echo " * Running Multisite install using wp core multisite-install --subdomains --url=\"${DOMAIN}\" --title=\"${SITE_TITLE}\" --admin_name=\"${ADMIN_USER}\" --admin_email=\"${ADMIN_EMAIL}\" --admin_password=\"${ADMIN_PASSWORD}\""
    noroot wp core multisite-install --subdomains --url="${DOMAIN}" --title="${SITE_TITLE}" --admin_name="${ADMIN_USER}" --admin_email="${ADMIN_EMAIL}" --admin_password="${ADMIN_PASSWORD}"
    echo " * Multisite install complete"
  elif [ "${WP_TYPE}" = "subdirectory" ]; then
    echo " * Running Multisite install using wp core ${INSTALL_COMMAND} --url=\"${DOMAIN}\" --title=\"${SITE_TITLE}\" --admin_name=\"${ADMIN_USER}\" --admin_email=\"${ADMIN_EMAIL}\" --admin_password=\"${ADMIN_PASSWORD}\""
    noroot wp core multisite-install --url="${DOMAIN}" --title="${SITE_TITLE}" --admin_name="${ADMIN_USER}" --admin_email="${ADMIN_EMAIL}" --admin_password="${ADMIN_PASSWORD}"
    echo " * Multisite install complete"
  fi

  DELETE_DEFAULT_PLUGINS=$(get_config_value 'delete_default_plugins' '')
  if [ ! -z "${DELETE_DEFAULT_PLUGINS}" ]; then
    echo " * Deleting the default plugins akismet and hello dolly"
    noroot wp plugin delete akismet
    noroot wp plugin delete hello
  fi

  maybe_import_test_content
}

update_wp() {
  if [[ $(noroot wp core version) > "${WP_VERSION}" ]]; then
    echo " * Installing an older version '${WP_VERSION}' of WordPress"
    noroot wp core update --version="${WP_VERSION}" --force
  else
    echo " * Updating WordPress '${WP_VERSION}'"
    noroot wp core update --version="${WP_VERSION}"
  fi
}

setup_cli() {
  rm -f "${VVV_PATH_TO_SITE}/wp-cli.yml"
  echo "# auto-generated file" > "${VVV_PATH_TO_SITE}/wp-cli.yml"
  echo "path: \"${PUBLIC_DIR}\"" >> "${VVV_PATH_TO_SITE}/wp-cli.yml"
  echo "@vvv:" >> "${VVV_PATH_TO_SITE}/wp-cli.yml"
  echo "  ssh: vagrant" >> "${VVV_PATH_TO_SITE}/wp-cli.yml"
  echo "  path: ${PUBLIC_DIR_PATH}" >> "${VVV_PATH_TO_SITE}/wp-cli.yml"
  echo "@${VVV_SITE_NAME}:" >> "${VVV_PATH_TO_SITE}/wp-cli.yml"
  echo "  ssh: vagrant" >> "${VVV_PATH_TO_SITE}/wp-cli.yml"
  echo "  path: ${PUBLIC_DIR_PATH}" >> "${VVV_PATH_TO_SITE}/wp-cli.yml"
}

restore_or_install() {

    echo " * WordPress is present but isn't installed to the database, checking for SQL dumps in content/${DB_DUMP}.gz or the main backup folder."
    if [ -f "${PUBLIC_DIR_PATH}/content/db/${DB_DUMP}.gz" ]; then
	    gzip -d ${PUBLIC_DIR_PATH}/content/db/${DB_DUMP}.gz;
      restore_db_backup "${PUBLIC_DIR_PATH}/content/db/${DB_DUMP}"
    elif [ "${DB_LINK}" != "" ]; then
      if [ ! -d "${PUBLIC_DIR_PATH}/content/db" ]; then
          mkdir "${PUBLIC_DIR_PATH}/content/db"
      fi
      echo " * Downloading database from dropbox"
      wget ${DB_LINK} -P "${PUBLIC_DIR_PATH}/content/db/"
      gzip -d ${PUBLIC_DIR_PATH}/content/db/${DB_DUMP}.gz;
      restore_db_backup "${PUBLIC_DIR_PATH}/content/db/${DB_DUMP}"
    elif [ -f "/srv/database/backups/${VVV_SITE_NAME}.sql" ]; then
      restore_db_backup "/srv/database/backups/${VVV_SITE_NAME}.sql"
    else
      install_wp
    fi

}

mkdir -p "${VVV_PATH_TO_SITE}"
cd "${VVV_PATH_TO_SITE}"
cp -r ../../tmp/* . 
rm -rf ../../tmp
#cp "${VVV_PATH_TO_SITE}/conf/.env-example" "${VVV_PATH_TO_SITE}/conf/.env"
#  wp-config credentials are all determined in the .env built here using template.env
sed -e "s|@@@DB_NAME@@@|${DB_NAME}|" -e "s|@@@DB_USER@@@|wp|" -e "s|@@@DB_PASSWORD@@@|wp|"  -e "s|@@@DB_PREFIX@@@|${DB_PREFIX}|" "${VVV_PATH_TO_SITE}/conf/template.env" > "${VVV_PATH_TO_SITE}/conf/.env"

setup_cli
setup_database
setup_nginx_folders
setup_composer_auth

if [ "${WP_TYPE}" == "none" ]; then
# echo " * wp_type was set to none, provisioning WP was skipped, moving to Nginx configs"
  echo " * wp_type was set to none, so provisioning WP as a dependency using composer along with other dependencies"
  if [[ -f "${PUBLIC_DIR_PATH}/composer.json" ]]; then
	  cd "${PUBLIC_DIR_PATH}"
	  echo " * Install WP as a dependency along with other dependencies"
  	noroot composer u
    if ! $(noroot wp core is-installed ); then
      #exit 1
      restore_or_install
      echo " * replacing all db references to the live domain with the dev domain"
      wp search-replace "${LIVE_URL}" "https://${DOMAIN}"
    fi
  fi
else
  echo " * Install type is '${WP_TYPE}'"
  # Install and configure the latest stable version of WordPress
  if [[ ! -f "${PUBLIC_DIR_PATH}/wp-load.php" ]]; then
    download_wordpress "${WP_VERSION}" "${WP_LOCALE}"
  fi

  if [[ ! -f "${PUBLIC_DIR_PATH}/wp-config.php" ]]; then
    initial_wpconfig
  fi

  if ! $(noroot wp core is-installed ); then
    echo " * SOMETHING HAS GONE WRONG"
    #exit 1
	  restore_or_install
  else
    update_wp
  fi
fi

copy_nginx_configs
setup_wp_config_constants
install_plugins
install_themes

echo " * Site Template provisioner script completed for ${VVV_SITE_NAME}"
