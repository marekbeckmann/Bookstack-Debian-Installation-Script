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

function installPackages() {
        msg_info "Updating system"
        apt-get -y update >/dev/null 2>&1
        apt-get -y full-upgrade >/dev/null 2>&1
        msg_ok "System updated"
        msg_info "Installing necessary packages"
        apt-get -y install wget pwgen unzip git curl apache2 libapache2-mod-php php mariadb-server mariadb-client mariadb-common php-{fpm,curl,mbstring,ldap,tidy,xml,zip,gd,mysql,cli} >/dev/null 2>&1
        msg_ok "All Packages installed"
}

function setupDB() {
        msg_info "Setting up database"
        bookstackpwd="$(pwgen -N 1 -s 96)" >/dev/null 2>&1
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
                cd "$installDir" || exit 1
                git clone https://github.com/BookStackApp/BookStack.git --branch release --single-branch "$installDir" >/dev/null 2>&1
                chown -R www-data: "$installDir"
                msg_ok "Bookstack downloaded successfully"

                msg_info "Installing Composer"
                curl -s https://getcomposer.org/installer -o composer-setup.php >/dev/null 2>&1
                php composer-setup.php --quiet
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
                tee /etc/apache2/sites-available/bookstack.conf >/dev/null <<EOT
<VirtualHost 127.0.0.1:8080>
        ServerName ${fqdn}
        ServerAdmin webmaster@localhost
        DocumentRoot $installDir/public/
    <Directory $installDir/public/>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
        <IfModule mod_rewrite.c>
            <IfModule mod_negotiation.c>
                Options -MultiViews -Indexes
            </IfModule>

            RewriteEngine On
            RewriteCond %{HTTP:Authorization} .
            RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteCond %{REQUEST_URI} (.+)/$
            RewriteRule ^ %1 [L,R=301]
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteCond %{REQUEST_FILENAME} !-f
            RewriteRule ^ index.php [L]
        </IfModule>
    </Directory>
</VirtualHost>
EOT
        fi

        a2enmod rewrite >/dev/null 2>&1
        if [ -f /etc/os-release ]; then
                . /etc/os-release
        fi
        if [[ "$VERSION_ID" = 11 ]]; then
                a2enmod proxy_fcgi setenvif >/dev/null 2>&1
                a2enconf php7.4-fpm >/dev/null 2>&1
        fi
        a2dissite 000-default.conf >/dev/null 2>&1
        a2ensite bookstack.conf >/dev/null 2>&1
        systemctl restart apache2 >/dev/null 2>&1
        msg_ok "Apache2 configured successfully"
}

function deploySSLCert() {
        if [[ "$nocert" != true ]]; then
                msg_error "Using Self Signed Certificate (Certbot failed)"
                msg_info "Creating Self Signed Certificate"
                openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=NA/ST=None/L=None/O=None/CN=${fqdn}" -keyout /etc/ssl/private/bookstack-selfsigned.key -out /etc/ssl/certs/bookstack-selfsigned.crt >/dev/null 2>&1
                sed -i "s/\/etc\/letsencrypt\/live\/${fqdn}\/fullchain.pem/\/etc\/ssl\/certs\/bookstack-selfsigned.crt/g" /etc/nginx/sites-available/"${fqdn}"
                sed -i "s/\/etc\/letsencrypt\/live\/${fqdn}\/privkey.pem/\/etc\/ssl\/private\/bookstack-selfsigned.key/g" /etc/nginx/sites-available/"${fqdn}"
                msg_ok "Self Signed Certificate created successfully"
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
                tee /etc/nginx/sites-available/"${fqdn}" >/dev/null <<EOT
upstream bookstack {
    server 127.0.0.1:8080;
}

server {
    server_name ${fqdn};
    listen [::]:443 ssl ipv6only=on;
    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/${fqdn}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${fqdn}/privkey.pem;

    location / {
        proxy_pass http://bookstack;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Nginx-Proxy true;
        proxy_redirect off;
}

}

server {

    listen 80 ;
    listen [::]:80 ;
    server_name ${fqdn};
    return 301 https://\$server_name\$request_uri;

}
EOT
        fi
        ln -s /etc/nginx/sites-available/"${fqdn}" /etc/nginx/sites-enabled/ >/dev/null 2>&1
        if [[ "$nocert" != true ]]; then
                msg_info "Requesting SSL Certificate"
                certbot --nginx --non-interactive --agree-tos --domains "${fqdn}" --email "${mail}" >/dev/null 2>&1 ||
                        msg_error "Certificate creation failed" &&
                        deploySSLCert
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
  [-d] [--domain] => Your BookStack Domain
  [-e] [--email] => Email for Certbot
  [-i] [--installdir] => Specifies the directory, BookStack will be installed in
  [-f] [--force] => Overrides existing files and directories, if needed
  [--no-cert] => Neither a Lets Encrypt nor a selfsigned certificate will be created
  [-u] [--update] => Updates existing BookStack Installation. Can be used with a different installation directory

More Documentation can be found on Github: https://github.com/marekbeckmann/Bookstack-Debian-Installation-Script"
}

function updateBS() {
        if [[ "$updateDir" = "" ]]; then
                updateDir="/var/www/bookstack"
        fi
        msg_info "Backuping up current instance to $HOME"
        tar cfvj ~/bookstack-web-bak-"$(date +"%m-%d-%Y")".tar.bz2 "$updateDir" >/dev/null 2>&1
        mysqldump -u root bookstack >~/bookstack-db-bak-"$(date +"%m-%d-%Y")".sql >/dev/null 2>&1
        msg_ok "Backup created successfully"
        msg_info "Updating Bookstack..."
        cd "$updateDir" || msg_error "BookStack Directory doesn't exist" && exit 1
        git reset --hard >/dev/null 2>&1
        git pull origin release >/dev/null 2>&1
        curl -s https://getcomposer.org/installer -o composer-setup.php >/dev/null 2>&1
        chown -R www-data: "$updateDir"
        php composer-setup.php --quiet
        rm -f composer-setup.php
        sudo -u www-data php composer.phar install --no-dev --no-plugins >/dev/null 2>&1
        chown -R root: "$updateDir" && chown -R www-data: "$updateDir"/{storage,bootstrap/cache,public/uploads}
        php artisan migrate --no-interaction --force >/dev/null 2>&1
        msg_ok "Bookstack updated successfully"
        msg_info "Cleaning Up Update"
        php artisan cache:clear
        php artisan config:clear
        php artisan view:clear
        msg_ok "Finished cleaning up"
}

function script_init() {
        if [[ "$fqdn" = "" ]]; then
                read -rp "Enter server FQDN [e.g docs.example.com]: " fqdn
        fi
        if [[ "$mail" = "" ]]; then
                read -rp "Enter Mail for Certbot: " mail
        fi
        if [[ "$fqdn" = "" ]] || [[ "$(whoami)" != "root" ]]; then
                clear
                msg_error "Script couldn't be executed!" --error
        else
                if [[ "$installDir" = "" ]]; then
                        installDir="/var/www/bookstack"
                fi
                installPackages
                setupDB
                setupBookstack
                configureApache
                configureNginx
                scriptSummary
        fi
}

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
                updateDir="$2"
                updateBS
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

script_init
