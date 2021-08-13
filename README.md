# Bookstack Debian 10 Installation Script

## How to use

### 1. Download script

```
git clone https://github.com/marekbeckmann/Bookstack-Debian-10-Installation-Script.git ~/install-bookstack
cd ~/install-bookstack && chmod +x install-bookstack-debian.sh
```
### 2. Run the script

```
sudo ./install-bookstack-debian.sh
```

After that, provide your desired FQDN, e.g. `docs.example.com` and a contact email for Let's Encrypt, e.g `webadmin@example.com`
The Script will then install Bookstack to `/var/www/bookstack`. It will furthermore setup NGINX to reverse proxy to Apache2 and configure SSL access. 
If you run your Bookstack instance locally or don't want to use Let's Encrypt certifiactes, you can create a self signed certificate using the command below. Then edit the NGINX VHOST and chane the filepaths for `ssl_certificate` and `ssl_certificate_key`.

```
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/bookstack.key -out /etc/ssl/certs/bookstack.crt
```





