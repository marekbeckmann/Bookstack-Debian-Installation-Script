#!/bin/bash

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
WARN="${YW}⚠${CL}"

# Default values (change here or by using the apropiate flags)
BACKUP_DIR="/root/bookstack-backups"
BOOKSTACK_DIR="/var/www/bookstack"
DB_NAME="bookstack"

DATE="$(date +%d-%m-%Y)"

function msg_info() {
        local msg="$1"
        echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
        local msg="$1"
        echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

function msg_error() {
        local msg="$1"
        echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

function msg_warning() {
        local msg="$1"
        echo -e "${BFR} ${WARN} ${YW}${msg}${CL}"
}

function errorHandler() {
        msg_error "$1"
        exit 1
}

function getIni() {
        startsection="$1"
        endsection="$2"
        output="$(awk "/$startsection/{ f = 1; next } /$endsection/{ f = 0 } f" "${configFile}")" >/dev/null 2>&1 || errorHandler "Unable to read ${configFile}"
}

function installPackages() {
        msg_info "Updating system"
        OLD_PHPVERSION=$(php -v 2>/dev/null | head -n 1 | cut -d" " -f 2 | cut -d"." -f 1-2)
        apt-get -y update >/dev/null 2>&1
        apt-get -y install lsb-release ca-certificates apt-transport-https software-properties-common gnupg2 >/dev/null 2>&1
        echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/sury-php.list >/dev/null 2>&1
        curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/sury-keyring.gpg >/dev/null 2>&1
        apt-get -y full-upgrade >/dev/null 2>&1
        msg_ok "System updated"
        msg_info "Installing necessary packages"
        apt-get -y install wget pwgen unzip git curl sudo apache2 libapache2-mod-php php mariadb-server mariadb-client mariadb-common php-{fpm,curl,mbstring,ldap,tidy,xml,zip,gd,mysql,cli} >/dev/null 2>&1
        PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1-2)
        update-alternatives --set php /usr/bin/php"${PHP_VERSION}" >/dev/null 2>&1
        systemctl enable --now php"${PHP_VERSION}"-fpm >/dev/null 2>&1
        msg_ok "All Packages installed"
}

function setupDB() {
        msg_info "Setting up database"
        bookstackpwd="$(pwgen -N 1 -s 96)" >/dev/null 2>&1
        # Check if database exists
        if [[ -n "$(mysql -u root -e "SHOW DATABASES LIKE 'bookstack'")" && -z "$force" ]]; then
                errorHandler "Database ${DB_NAME} already exists, aborting..."
        elif [[ -n "$(mysql -u root -e "SHOW DATABASES LIKE 'bookstack'")" && -n "$force" ]]; then
                msg_warning "Database ${DB_NAME} already exists, deleting..."
                mysql -u root -e "DROP DATABASE bookstack" >/dev/null 2>&1
                mysql -u root -e "DROP USER 'bookstack'@'localhost'" >/dev/null 2>&1
        fi
        mysql -u root -e "CREATE DATABASE bookstack" >/dev/null 2>&1
        mysql -u root -e "DROP USER ''@'localhost'" >/dev/null 2>&1
        mysql -u root -e "DROP USER ''@'$(hostname)'" >/dev/null 2>&1
        mysql -u root -e "DROP DATABASE test" >/dev/null 2>&1
        mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')" >/dev/null 2>&1
        mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'" >/dev/null 2>&1
        mysql -u root -e "FLUSH PRIVILEGES" >/dev/null 2>&1
        mysql -u root -e "CREATE DATABASE bookstack" >/dev/null 2>&1
        mysql -u root -e "CREATE USER 'bookstack'@'localhost' IDENTIFIED BY '$bookstackpwd'" >/dev/null 2>&1
        mysql -u root -e "GRANT ALL ON bookstack.* TO 'bookstack'@'localhost'" >/dev/null 2>&1
        mysql -u root -e "FLUSH PRIVILEGES" >/dev/null 2>&1
        msg_ok "Database setup finished successfully"
}

function setupBookstack() {
        if [[ -n "$(ls -A "$installDir" >/dev/null 2>&1)" ]] && [[ "$force" != true ]]; then
                msg_error "Directory not empty. Use -f to force install"
                exit 1
        else
                if [[ "$force" = true ]]; then
                        rm -rf "${installDir:?}/" >/dev/null 2>&1
                fi
                msg_info "Getting latest bookstack release"
                mkdir -p "$installDir"
                cd "$installDir" || errorHandler "Failed to access bookstack directory"
                git clone https://github.com/BookStackApp/BookStack.git --branch release --single-branch "$installDir" >/dev/null 2>&1
                chown -R www-data: "$installDir" >/dev/null 2>&1
                msg_ok "Bookstack downloaded successfully"
                msg_info "Installing Composer"
                curl -s https://getcomposer.org/installer -o composer-setup.php >/dev/null 2>&1
                php composer-setup.php --quiet >/dev/null 2>&1
                rm -f composer-setup.php >/dev/null 2>&1
                sudo -u www-data php composer.phar install --no-dev --no-plugins >/dev/null 2>&1
                msg_ok "Composer installed successfully"
                msg_info "Configuring Bookstack Settings..."
                mv .env.example .env
                chown -R root: "$installDir" && sudo chown -R www-data: "$installDir"/{storage,bootstrap/cache,public/uploads}
                chmod -R 0755 "$installDir"
                sed -i "s/https:\/\/example.com/https\:\/\/$fqdn/g" .env
                sed -i 's/database_database/bookstack/g' .env
                sed -i 's/database_username/bookstack/g' .env
                sed -i "s/database_user_password/\"$bookstackpwd\"/g" .env
                php artisan key:generate --no-interaction --force >/dev/null 2>&1
                php artisan migrate --no-interaction --force >/dev/null 2>&1
                msg_ok "Bookstack Settings configured successfully"
        fi
}

function configureApache() {
        msg_info "Setting up Apache2"
        echo "Listen 127.0.0.1:8080" | tee /etc/apache2/ports.conf >/dev/null 2>&1
        if [[ -n "$(ls -A /etc/apache2/sites-available/bookstack.conf >/dev/null 2>&1)" ]] && [[ "$force" != true ]]; then
                msg_error "Bookstack VHOST already exists. Use -f to force install"
                exit 1
        else
                getIni "START_APACHECONF" "END_APACHECONF"
                printf "%s" "$output" | tee /etc/apache2/sites-available/bookstack.conf >/dev/null 2>&1
                sed -i "s/FQDN/${fqdn}/g" /etc/apache2/sites-available/bookstack.conf
                sed -i "s/INSTALLDIR/${installDir//\//\\/}/g" /etc/apache2/sites-available/bookstack.conf
        fi

        a2enmod rewrite >/dev/null 2>&1
        if [ -f /etc/os-release ]; then
                . /etc/os-release
        else
                msg_warning "Failed to get OS Version"
        fi
        if [[ "$VERSION_ID" = 11 ]]; then
                a2enmod proxy_fcgi setenvif >/dev/null 2>&1
                a2dismod php"${OLD_PHPVERSION}" >/dev/null 2>&1
                a2enmod php"${PHP_VERSION}" >/dev/null 2>&1
                a2disconf php"${OLD_PHPVERSION}"-fpm >/dev/null 2>&1
                a2enconf php"${PHP_VERSION}"-fpm >/dev/null 2>&1
        fi
        a2dissite 000-default.conf >/dev/null 2>&1
        a2ensite bookstack.conf >/dev/null 2>&1
        systemctl restart apache2 >/dev/null 2>&1
        msg_ok "Apache2 configured successfully"
}

function deploySSLCert() {
        if [[ "$nocert" != true ]]; then
                msg_warning "Using Self Signed Certificate (Certbot failed)"
                msg_info "Creating Self Signed Certificate"
                openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=NA/ST=None/L=None/O=None/CN=${fqdn}" -keyout /etc/ssl/private/bookstack-selfsigned.key -out /etc/ssl/certs/bookstack-selfsigned.crt >/dev/null 2>&1
                sed -i "s/\/etc\/letsencrypt\/live\/${fqdn}\/fullchain.pem/\/etc\/ssl\/certs\/bookstack-selfsigned.crt/g" /etc/nginx/sites-available/"${fqdn}"
                sed -i "s/\/etc\/letsencrypt\/live\/${fqdn}\/privkey.pem/\/etc\/ssl\/private\/bookstack-selfsigned.key/g" /etc/nginx/sites-available/"${fqdn}"
        else
                msg_error "Certificate creation failed."
        fi
}

function configureNginx() {
        msg_info "Installing and setting up Nginx"
        apt-get -y install nginx certbot python3-certbot-nginx >/dev/null 2>&1
        rm /etc/nginx/sites-enabled/default >/dev/null 2>&1
        if [[ -n "$(ls -A /etc/nginx/sites-available/"${fqdn}" >/dev/null 2>&1)" ]] && [[ "$force" != true ]]; then
                msg_error "Nginx config already exists. Use -f to force install"
                exit 1
        else
                getIni "START_NGINXCONF" "END_NGINXCONF"
                printf "%s" "$output" | tee /etc/nginx/sites-available/"${fqdn}" >/dev/null 2>&1
                sed -i "s/FQDN/${fqdn}/g" /etc/nginx/sites-available/"${fqdn}"
        fi
        ln -s /etc/nginx/sites-available/"${fqdn}" /etc/nginx/sites-enabled/ >/dev/null 2>&1
        if [[ "$nocert" != true ]]; then
                msg_info "Requesting SSL Certificate"
                certbot --nginx --non-interactive --agree-tos --domains "${fqdn}" --email "${mail}" >/dev/null 2>&1 || {
                        msg_error "Let's Encrypt Certificate creation failed" && deploySSLCert
                }
                msg_ok "SSL Certificate created successfully"
        else
                msg_ok "Skipping Certbot"
        fi
}

function scriptSummary() {
        systemctl restart nginx >/dev/null 2>&1
        msg_ok "Bookstack installed successfully"

        printf '%s\n' "
Installation complete!
If Certbot failed, a self-signed certificate was created for you, unless you specified not to.
How to login:
  Bookstack URL: https://$fqdn
  Email: admin@admin.com
  Password: password"

}

function helpMsg() {
        printf '%s\n' "Help for BookStack Installation Script (Debian 10/11)

You can use the following Options:

  [-h] => Help Dialog
  [-v] => Show installed Version (requires -l <bookstack-dir>)
  [-c] [--config] => Path to custom config file
  [-d] [--domain] => Your BookStack Domain
  [-e] [--email] => Email for Certbot
  [-i] [--installdir] => Specifies the directory, BookStack will be installed in
  [-f] [--force] => Overrides existing files and directories, if needed
  [--no-cert] => Neither a Lets Encrypt nor a selfsigned certificate will be created
  [-u] [--update] => Updates existing BookStack Installation. Can be used with a different installation directory
  [-b] [--backup-dir] => Specifies the directory, where backups will be stored
  [-l] [--bookstack-dir] => Specifies the directory, where BookStack is installed
  [--db] => Specifies name of the Bookstack database you want to backup

More Documentation can be found on Github: https://github.com/marekbeckmann/Bookstack-Debian-Installation-Script"
}

function backup() {
        msg_info "Backing up Bookstack"
        BACKUP_DEST="$BACKUP_DIR"/Backup_"${DATE}"
        mkdir -p "$BACKUP_DEST" >/dev/null 2>&1
        zip -r "${BACKUP_DEST}"/bookstack-web-bak.zip "${BOOKSTACK_DIR}" >/dev/null 2>&1
        mysqldump -u root "${DB_NAME}" >"${BACKUP_DEST}"/"${DB_NAME}"-db-bak.sql >/dev/null 2>&1 || errorHandler "Failed to backup database, aborting"
        msg_ok "Backup complete!"
        updateBS
}

function checkBookstack() {
        msg_info "Checking Bookstack installation..."
        zipInstalled="$(zip -v >/dev/null 2>&1 && echo "true" || echo "false")"
        if [[ "$zipInstalled" == "false" ]]; then
                msg_error "Zip utility not installed, aborting"
                exit 1
        fi
        sudoInstalled="$(sudo -V >/dev/null 2>&1 && echo "true" || echo "false")"
        if [[ "$sudoInstalled" == "false" ]]; then
                msg_error "Sudo utility not installed, aborting"
                exit 1
        fi
        CURRENT_VERS="$(cat "${BOOKSTACK_DIR}"/version 2>/dev/null)"
        if [[ $? -ne 0 ]]; then
                msg_error "Bookstack not found in ${BOOKSTACK_DIR}"
                exit 1
        else
                msg_ok "Found Bookstack version ${CURRENT_VERS}"
        fi
        backup
}

function updateBS() {
        cd "${BOOKSTACK_DIR}" || errorHandler "Failed to change directory to ${BOOKSTACK_DIR}, aborting"
        msg_info "Getting latest Bookstack release"
        chown -R www-data:www-data "${BOOKSTACK_DIR}"
        git reset --hard >/dev/null 2>&1
        git pull origin release >/dev/null 2>&1
        msg_ok "Latest Bookstack release downloaded"
        msg_info "Updating Bookstack"
        curl -s https://getcomposer.org/installer -o composer-setup.php >/dev/null 2>&1
        php composer-setup.php --quiet >/dev/null 2>&1
        rm -f composer-setup.php >/dev/null 2>&1
        sudo -u www-data composer install --no-dev >/dev/null 2>&1
        chown -R root: "${BOOKSTACK_DIR}" && chown -R www-data: "${BOOKSTACK_DIR}"/{storage,bootstrap/cache,public/uploads}
        php artisan migrate --no-interaction --force >/dev/null 2>&1
        msg_ok "Bookstack updated successfully"
        msg_info "Finishing up"
        php artisan cache:clear >/dev/null 2>&1
        php artisan config:clear >/dev/null 2>&1
        php artisan view:clear >/dev/null 2>&1
        msg_ok "Cleanup finished"
        NEW_VERS="$(cat "${BOOKSTACK_DIR}"/version)"
        msg_ok "Bookstack updated from ${CURRENT_VERS} to ${NEW_VERS}"
        exit 0
}

function getVersion() {
        if [[ -f "${BOOKSTACK_DIR}"/version ]]; then
                CURRENT_VERS="$(cat "${BOOKSTACK_DIR}"/version 2>/dev/null)"
                msg_ok "Found Bookstack version ${CURRENT_VERS} in ${BOOKSTACK_DIR}"
                exit 0
        else
                errorHandler "Bookstack not found in ${BOOKSTACK_DIR}"
        fi
}

function script_init() {
        getParams "$@"
        if [[ "$fqdn" = "" ]]; then
                read -rp "Enter server FQDN [e.g docs.example.com]: " fqdn
        fi
        if [[ "$mail" = "" && "$nocert" != true ]]; then
                read -rp "Enter Mail for Certbot: " mail
        fi
        if [[ -z "$configFile" ]]; then
                configFile="$(dirname "$0")/config.ini"
                configFile="$(realpath "$configFile")"
        fi
        if [[ -z "$installDir" ]]; then
                installDir="/var/www/bookstack"
        fi
        if [[ "$fqdn" = "" ]] || [[ "$EUID" != 0 ]]; then
                clear
                msg_error "Script couldn't be executed!"
        else
                installPackages
                setupDB
                setupBookstack
                configureApache
                configureNginx
                scriptSummary
        fi
}
function getParams() {
        while test $# -gt 0; do
                case "$1" in
                -h | --help)
                        helpMsg
                        ;;
                -d | --domain)
                        fqdn="$2"
                        ;;
                -i | --installdir)
                        installDir="$2"
                        ;;
                -e | --email)
                        mail="$2"
                        ;;
                --no-cert)
                        nocert=true
                        ;;
                -f | --force)
                        force=true
                        ;;
                -u | --update)
                        checkBookstack
                        ;;
                -b | --backup-dir)
                        BACKUP_DIR="$2"
                        ;;
                -l | --bookstack-dir)
                        BOOKSTACK_DIR="$2"
                        ;;
                --db)
                        DB_NAME="$2"
                        ;;
                -c | --config)
                        configFile="$2"
                        ;;
                -v | --version)
                        getVersion
                        ;;
                --*)
                        msg_error "Unknown option $1"
                        helpMsg
                        exit 1
                        ;;
                -*)
                        msg_error "Unknown option $1"
                        helpMsg
                        exit 1
                        ;;
                esac
                shift
        done
}
script_init "$@"
