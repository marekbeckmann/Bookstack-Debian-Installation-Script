#!/bin/bash

function logToScreen() {
        clear
        if [[ "$2" = "--success" ]]; then
                printf '%s\n' "$(tput setaf 2)$1 $(tput sgr 0)"
        elif [[ "$2" = "--error" ]]; then
                printf '%s\n' "$(tput setaf 1)$1 $(tput sgr 0)"
        else
                printf '%s\n' "$(tput setaf 3)$1 $(tput sgr 0)"
        fi
        sleep 1
}

function installPackages() {
        logToScreen "Installing required pacakges..."
        apt -y update
        apt -y install wget pwgen unzip git curl apache2 libapache2-mod-php php mariadb-server mariadb-client mariadb-common php-{fpm,curl,mbstring,ldap,tidy,xml,zip,gd,mysql,cli}
}

function setupDB() {
        logToScreen "Setting up Database..."
        bookstackpwd="$(pwgen -N 1 -s 96)"
        mysql -u root -e "DROP USER ''@'localhost'"
        mysql -u root -e "DROP USER ''@'$(hostname)'"
        mysql -u root -e "DROP DATABASE test"
        mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
        mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'"
        mysql -u root -e "FLUSH PRIVILEGES"
        mysql -u root -e "CREATE DATABASE bookstack"
        mysql -u root -e "CREATE USER 'bookstack'@'localhost' IDENTIFIED BY '$bookstackpwd'"
        mysql -u root -e "GRANT ALL ON bookstack.* TO 'bookstack'@'localhost'"
        mysql -u root -e "FLUSH PRIVILEGES"
}

function setupBookstack() {
        logToScreen "Downloading latest Bookstack release..."
        if [[ -n "$(ls -A "$installDir")" ]] && [[ "$force" != true ]]; then
                logToScreen "Installation Directory $installDir is not empty!
        Please choose a different directory or use --force to override existing files"
                exit 1
        else
                if [[ "$force" = true ]]; then
                        rm -rf "${installDir:?}/"
                fi
                mkdir -p "$installDir"
                cd "$installDir" || exit 1
                git clone https://github.com/BookStackApp/BookStack.git --branch release --single-branch "$installDir"
                chown -R www-data: "$installDir"

                logToScreen "Installing Composer"
                curl -s https://getcomposer.org/installer >composer-setup.php
                php composer-setup.php --quiet
                rm -f composer-setup.php
                sudo -u www-data php composer.phar install --no-dev --no-plugins

                logToScreen "Configuring Bookstack Settings..."
                mv .env.example .env
                chown -R root: "$installDir" && sudo chown -R www-data: "$installDir"/{storage,bootstrap/cache,public/uploads}
                chmod -R 0755 "$installDir"
                sed -i "s/https:\/\/example.com/https\:\/\/$fqdn/g" .env
                sed -i 's/database_database/bookstack/g' .env
                sed -i 's/database_username/bookstack/g' .env
                sed -i "s/database_user_password/\"$bookstackpwd\"/g" .env
                php artisan key:generate --no-interaction --force
                php artisan migrate --no-interaction --force
        fi

}

function configureApache() {
        logToScreen "Setting up Apache2 VHOST"
        echo "Listen 127.0.0.1:8080" | tee /etc/apache2/ports.conf
        if [[ -n "$(ls -A /etc/apache2/sites-available/bookstack.conf)" ]] && [[ "$force" != true ]]; then
                logToScreen "Apache2 Config already exists!
        Use --force to override existing files"
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

        a2enmod rewrite
        if [ -f /etc/os-release ]; then
                . /etc/os-release
        fi
        if [[ "$VERSION_ID" = 11 ]]; then
                a2enmod proxy_fcgi setenvif
                a2enconf php7.4-fpm
        fi
        a2dissite 000-default.conf
        a2ensite bookstack.conf
        systemctl restart apache2
}

function deploySSLCert() {
        if [[ "$nocert" != true ]]; then
                logToScreen "Using Self Signed Certificate (Certbot failed)..."
                openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=NA/ST=None/L=None/O=None/CN=${fqdn}" -keyout /etc/ssl/private/bookstack-selfsigned.key -out /etc/ssl/certs/bookstack-selfsigned.crt
                sed -i "s/\/etc\/letsencrypt\/live\/${fqdn}\/fullchain.pem/\/etc\/ssl\/certs\/bookstack-selfsigned.crt/g" /etc/nginx/sites-available/"${fqdn}"
                sed -i "s/\/etc\/letsencrypt\/live\/${fqdn}\/privkey.pem/\/etc\/ssl\/private\/bookstack-selfsigned.key/g" /etc/nginx/sites-available/"${fqdn}"
        else
                logToScreen "Skipping Self-Signed Certificate"
        fi
}

function configureNginx() {
        logToScreen "Installing and setting up NGINX"
        apt -y install nginx certbot python3-certbot-nginx
        rm /etc/nginx/sites-enabled/default
        if [[ -n "$(ls -A /etc/nginx/sites-available/"${fqdn}")" ]] && [[ "$force" != true ]]; then
                logToScreen "NGINX Config already exists!
        Use --force to override existing files"
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
        ln -s /etc/nginx/sites-available/"${fqdn}" /etc/nginx/sites-enabled/
        if [[ "$nocert" != true ]]; then
                certbot --nginx --non-interactive --agree-tos --domains "${fqdn}" --email "${mail}" || deploySSLCert
        else
                logToScreen "Skipping Certbot"
        fi
}

function scriptSummary() {
        systemctl restart nginx
        logToScreen "Installation complete!
        If Certbot failed, a self signed certificate was created for you, unless you specified not to.
        How to login:
        Server-Address: http://$fqdn
        Email: admin@admin.com
        Password: password" --success

}

function helpMsg() {
        logToScreen "Help for BookStack Installation Script (Debian 10/11)

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
        logToScreen "Creating Backup to $HOME..."
        tar cfvj ~/bookstack-web-bak-"$(date +"%m-%d-%Y")".tar.bz2 "$updateDir"
        mysqldump -u root bookstack >~/bookstack-db-bak-"$(date +"%m-%d-%Y")".sql
        logToScreen "Updating Bookstack..."
        cd "$updateDir" || logToScreen "BookStack Directory doesn't exist" --error && exit 1
        git reset --hard
        git pull origin release
        curl -s https://getcomposer.org/installer >composer-setup.php
        chown -R www-data: "$updateDir"
        php composer-setup.php --quiet
        rm -f composer-setup.php
        sudo -u www-data php composer.phar install --no-dev --no-plugins
        chown -R root: "$updateDir" && chown -R www-data: "$updateDir"/{storage,bootstrap/cache,public/uploads}
        php artisan migrate --no-interaction --force
        logToScreen "Cleaning Up Update..."
        php artisan cache:clear
        php artisan config:clear
        php artisan view:clear
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
                logToScreen "Script couldn't be executed!" --error
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
                logToScreen "Unknown option $1" --error
                helpMsg
                exit 1
                ;;
        -*)
                logToScreen "Unknown option $1" --error
                helpMsg
                exit 1
                ;;
        esac
        shift
done

script_init
