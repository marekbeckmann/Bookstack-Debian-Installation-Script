# Bookstack Debian 10/11 Installation Script

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

You can run the script with the following parameters: 

<table border="1" id="bkmrk--h---help-prints-hel" style="border-collapse: collapse; width: 100%; height: 211px;"><tbody><tr style="height: 30px;"><td style="width: 30.7408%; height: 30px;">`-h` `--help`</td><td style="width: 69.2592%; height: 30px;">Prints Help Message, that shows all options and a short description</td></tr><tr style="height: 29px;"><td style="width: 30.7408%; height: 29px;">`-d` `--domain` `<domain>`</td><td style="width: 69.2592%; height: 29px;">Specifies domain for BookStack server</td></tr><tr style="height: 29px;"><td style="width: 30.7408%; height: 29px;">`-e` `--email` `<email>`</td><td style="width: 69.2592%; height: 29px;">Specifies email for Certbot</td></tr><tr style="height: 35px;"><td style="width: 30.7408%; height: 35px;">`-i` `--installdir` `<directory>`

</td><td style="width: 69.2592%; height: 35px;">Specifies installation directory (Defaults to `/var/www/bookstack`)</td></tr><tr style="height: 29px;"><td style="width: 30.7408%; height: 29px;">`-f` `--force`</td><td style="width: 69.2592%; height: 29px;">Overrides existing files and directories</td></tr><tr style="height: 30px;"><td style="width: 30.7408%; height: 30px;">`-u` `--update` `<directory>`</td><td style="width: 69.2592%; height: 30px;">Updates bookstack installation in specified directory (Defaults to `/var/www/bookstack`)</td></tr><tr style="height: 29px;"><td style="width: 30.7408%; height: 29px;">`--no-cert`</td><td style="width: 69.2592%; height: 29px;">Doesn't attempt to create a SSL certificate (NGINX config will fail)</td></tr></tbody></table>



After that, provide your desired FQDN, e.g. `docs.example.com` and a contact email for Let's Encrypt, e.g `webadmin@example.com`
The Script will then install Bookstack to `/var/www/bookstack`. It will furthermore setup NGINX to reverse proxy to Apache2 and configure SSL access. 
If Certbot fails to create a Let's Encrypt Certificate, the script will automatically set up a self-signed Certificate. This certificate should, at most, be used for internal purposes. 





