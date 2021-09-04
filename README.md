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


| Option | Description |
|--|--|
| `-h` `--help` | Prints help message, that shows all options and a short description |
| `-d` `--domain` `<domain>` | Specifies domain for BookStack server |
| `-e` `--email` `<email>` | Specifies email for Certbot |
| `-i` `--installdir` `<directory>` | Specifies installation directory (Defaults to `/var/www/bookstack`) |
| `-f` `--force` | Overrides existing files and directories |
| `-u` `--update` `<directory>` | Updates bookstack installation in specified directory (Defaults to `/var/www/bookstack`) |
| `--no-cert` | Doesn't attempt to create a SSL certificate (NGINX config will fail) |


**Example:**
```
sudo ./install-bookstack-debian.sh -d docs.example.com -e admin@example.com -i /var/www/bookstack1 -f
```

If you don't provide a domain/email when running the script, it will be queried interactively.

Without any options, the script will then install Bookstack to `/var/www/bookstack`. It will furthermore setup NGINX to reverse proxy to Apache2 and configure SSL access. 
If Certbot fails to create a Let's Encrypt Certificate (e.g a on a local machine), the script will automatically set up a self-signed Certificate. This certificate should, at most, be used for internal purposes. 
