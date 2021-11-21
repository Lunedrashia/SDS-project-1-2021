#!/bin/bash
sudo apt update -y
sudo apt install -y mariadb-server
sudo systemctl start mariadb

mysql --user=root <<EOF
    UPDATE mysql.user SET Password=PASSWORD('${database_root_pass}') WHERE User='root';
    DELETE FROM mysql.user WHERE User='';
    DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
    CREATE DATABASE ${database_name};
    CREATE USER '${database_user}'@'%' identified by '${database_pass}';
    grant all privileges on *.* to '${database_user}'@'%' identified by '${database_pass}' with grant option;
    FLUSH PRIVILEGES;
EOF

sudo systemctl enable mariadb.service
sudo sh -c 'echo "bind-address = 0.0.0.0" >> /etc/mysql/my.cnf'
sudo systemctl restart mariadb

touch 1.txt