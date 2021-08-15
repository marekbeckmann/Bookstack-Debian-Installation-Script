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
If Certbot fails to create a Let's Encrypt Certificate, the script will automatically set up a self-signed Certificate. This certificate should, at most, be used for internal purposes. 





