# Bookstack Debian 10/11 Installation Script

## How to use

### 1. Download script

```
git clone https://github.com/marekbeckmann/Bookstack-Debian-Installation-Script.git ~/install-bookstack
cd ~/install-bookstack && chmod +x install-bookstack-debian.sh
```
### 2. Run the script

```
sudo ./install-bookstack-debian.sh
```

You can run the script with the following parameters: 

| Option                            | Description                                                                  | Required |
| --------------------------------- | ---------------------------------------------------------------------------- | -------- |
| `-h` `--help`                     | Prints help message, that shows all options and a short description          | ❌        |
| `-v` `--version`                  | Prints version of installed Bookstack (in combination with `-l <directory>`) | ❌        |
| `-c` `--config` `<file>`          | Specifies custom config file (Defaults to `config.ini`)                      | ❌        |
| `-d` `--domain` `<domain>`        | Specifies domain for BookStack server                                        | ✅        |
| `-e` `--email` `<email>`          | Specifies email for Certbot                                                  | ✅        |
| `-i` `--installdir` `<directory>` | Specifies installation directory (Defaults to `/var/www/bookstack`)          | ❌        |
| `-f` `--force`                    | Overrides existing files and directories                                     | ❌        |
| `--no-cert`                       | Doesn't attempt to create a SSL certificate (NGINX config will fail)         | ❌        |

**Example:**
```
sudo ./install-bookstack-debian.sh -d docs.example.com -e admin@example.com
```bash
This will install Bookstack to `/var/www/bookstack1` and create an SSL certificate for the domain `docs.example.com`. If any files/directories already exist, the script will abort and warn you about it. Please use the `-f` option cautiously.

If you don't provide a domain when running the script, it will be queried interactively.
Without any options, the script will then install Bookstack to `/var/www/bookstack`. It will furthermore setup NGINX to reverse proxy to Apache2 and configure SSL access. 
If Certbot fails to create a Let's Encrypt Certificate (e.g a on a local machine), the script will automatically set up a self-signed Certificate. This certificate should, at most, be used for internal purposes. 

You can use the update function with the following parameters:

| Option                               | Description                                                                              | Required |
| ------------------------------------ | ---------------------------------------------------------------------------------------- | -------- |
| `-u` `--update`                      | Updates bookstack installation in specified directory (Defaults to `/var/www/bookstack`) | ✅        |
| `-b` `--backup-dir` `<directory>`    | Specifies backup directory (Defaults to `/var/www/bookstack-backup`)                     | ❌        |
| `-l` `--bookstack-dir` `<directory>` | Specifies bookstack directory (Defaults to `/var/www/bookstack`)                         | ❌        |
| `--db` `<database>`                  | Specifies database name (Defaults to `bookstack`)                                        | ❌        |

**Example:**
```bash
sudo ./install-bookstack-debian.sh -u -b /mnt/backup
```
**IMPORTANT**: If your Bookstack installation is not located in `/var/www/bookstack`, you have to specify the directory with `-l <directory>`. Please make sure to specify `-l <directory>` before `-u` or `--update`.



