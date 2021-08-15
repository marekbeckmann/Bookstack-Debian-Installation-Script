#!/bin/bash

function logToScreen() {
        clear
        printf '%s\n' "$(tput setaf 2)$1 $(tput sgr 0)"
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

function setupBookstack(){
        logToScreen "Downloading latest Bookstack release..."
        mkdir -p /var/www/bookstack
        cd /var/www/bookstack || exit 1
        git clone https://github.com/BookStackApp/BookStack.git --branch release --single-branch /var/www/bookstack
        chown -R www-data: /var/www/bookstack

        logToScreen "Installing Composer"
        curl -s https://getcomposer.org/installer > composer-setup.php
        php composer-setup.php --quiet
        rm -f composer-setup.php
        sudo -u www-data php composer.phar install --no-dev --no-plugins

        logToScreen "Configuring Bookstack Settings..."
        mv .env.example .env
        chown -R root: /var/www/bookstack && sudo chown -R www-data: /var/www/bookstack/{storage,bootstrap/cache,public/uploads}
        chmod -R 0755 /var/www/bookstack
        sed -i "s/https:\/\/example.com/https\:\/\/$fqdn/g" .env
        sed -i 's/database_database/bookstack/g' .env
        sed -i 's/database_username/bookstack/g' .env
        sed -i "s/database_user_password/\"$bookstackpwd\"/g" .env
        php artisan key:generate --no-interaction --force
        php artisan migrate --no-interaction --force

}

function configureApache(){
        logToScreen "Setting up Apache2 VHOST"
        echo "Listen 127.0.0.1:8080" | tee /etc/apache2/ports.conf
        tee /etc/apache2/sites-available/bookstack.conf >/dev/null <<EOT
<VirtualHost 127.0.0.1:8080>
        ServerName ${fqdn}
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/bookstack/public/
    <Directory /var/www/bookstack/public/>
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

a2enmod rewrite
a2dissite 000-default.conf
a2ensite bookstack.conf
systemctl restart apache2
}

function deploySSCert(){
        logToScreen "Using Self Signed Certificate (Certbot failed)..."
        openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=NA/ST=None/L=None/O=None/CN=${fqdn}" -keyout /etc/ssl/private/bookstack-selfsigned.key -out /etc/ssl/certs/bookstack-selfsigned.crt
        sed -i "s/\/etc\/letsencrypt\/live\/${fqdn}\/fullchain.pem/\/etc\/ssl\/certs\/bookstack-selfsigned.crt/g" /etc/nginx/sites-available/"${fqdn}"
        sed -i "s/\/etc\/letsencrypt\/live\/${fqdn}\/privkey.pem/\/etc\/ssl\/private\/bookstack-selfsigned.key/g" /etc/nginx/sites-available/"${fqdn}"
}

function configureNginx(){
        logToScreen "Installing and setting up NGINX"
        apt -y install nginx certbot python3-certbot-nginx
        rm /etc/nginx/sites-enabled/default
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
ln -s /etc/nginx/sites-available/"${fqdn}" /etc/nginx/sites-enabled/
certbot --nginx --non-interactive --agree-tos --domains "${fqdn}" --email "${mail}" || deploySSCert
}

function scriptSummary(){
        systemctl restart nginx
        logToScreen "Installation complete!
        If Certbot failed, a self signed certificate was created for you.
        How to login:
        Server-Address: https://$fqdn
        Email: admin@admin.com
        Password: password"

}

function script_init() {
        read -rp "Enter server FQDN [docs.example.com]: " fqdn
        read -rp "Enter Mail for Certbot: " mail
        if [ "$fqdn" = "" ] || [ "$(whoami)" != "root" ] || [ "$mail" = "" ]; then
                clear
                echo "Script aborted!"
        else
                installPackages
                setupDB
                setupBookstack
                configureApache
                configureNginx
                scriptSummary
        fi
}

script_init
