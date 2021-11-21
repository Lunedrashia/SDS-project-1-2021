#!/bin/bash

touch 0.txt

sudo apt update -y
sudo apt install -y apache2 mariadb-server libapache2-mod-php7.4
sudo apt install -y php7.4-gd php7.4-mysql php7.4-curl php7.4-mbstring php7.4-intl
sudo apt install -y php7.4-gmp php7.4-bcmath php-imagick php7.4-xml php7.4-zip
sudo wget https://download.nextcloud.com/server/releases/latest.tar.bz2
sudo tar -xjf latest.tar.bz2

touch 1.txt

cat << EOF > nextcloud/config/storage.config.php
<?php
\$CONFIG = array (
    "objectstore" => array( 
        "class" => "OC\\Files\\ObjectStore\\S3",
        "arguments" => array(
            "bucket" => "${s3_bucket_name}",
            "key"    => "${user_access_key}",
            "secret" => "${user_secret_key}",
            "use_ssl" => true,
            "region" => "${aws_region}"
        ),
    ),
);
EOF

touch 2.txt

cat << EOF > /etc/apache2/sites-available/nextcloud.conf
<VirtualHost *:80>
    DocumentRoot /var/www/nextcloud
    <Directory /var/www/nextcloud/>
        Require all granted
        Options FollowSymlinks MultiViews
        AllowOverride All
        <IfModule mod_dav.c>
            Dav off
        </IfModule>
        SetEnv HOME /var/www/nextcloud
        SetEnv HTTP_HOME /var/www/nextcloud
    </Directory>
    ErrorLog  /var/log/apache2/nextcloud_error.log
    CustomLog /var/log/apache2/nextcloud_access.log combined
</VirtualHost>
EOF

touch 3.txt

cat << EOF > nextcloud/config/autoconfig.php
<?php
\$AUTOCONFIG = array(
    "dbtype"        => "mysql",
    "dbname"        => "${database_name}",
    "dbuser"        => "${database_user}",
    "dbpass"        => "${database_pass}",
    "dbhost"        => "${database_adr}",
    "dbtableprefix" => "",
    "adminlogin"    => "${admin_user}",
    "adminpass"     => "${admin_pass}",
    "directory"     => "/var/www/nextcloud/data",
);
EOF

touch 4.txt

chown -R www-data:www-data nextcloud/
sudo mv nextcloud/ /var/www
a2ensite nextcloud.conf
a2enmod rewrite
a2enmod headers
a2enmod env
a2enmod dir
a2enmod mime
a2dissite 000-default
a2ensite nextcloud
sudo service apache2 restart

touch 5.txt