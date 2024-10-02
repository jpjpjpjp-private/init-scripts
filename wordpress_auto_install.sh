#!/bin/bash

# === WordPress Auto-Installation Script for both Debian and CentOS ===

# Detect operating system type (Debian/Ubuntu or CentOS/RHEL)
if [ -f /etc/debian_version ]; then
    OS_TYPE="debian"
    PKG_MANAGER="apt-get"
    APACHE_SERVICE="apache2"
    PHP_PACKAGE="php libapache2-mod-php php-mysql php-curl php-json php-cgi php-gd"
    MYSQL_SERVICE_NAME="mysql"
elif [ -f /etc/centos-release ] || [ -f /etc/redhat-release ]; then
    OS_TYPE="centos"
    PKG_MANAGER="yum"
    APACHE_SERVICE="httpd"
    PHP_PACKAGE="php php-mysqlnd php-curl php-json php-gd"
    MYSQL_SERVICE_NAME="mariadb"
else
    echo "Unsupported OS. Exiting."
    exit 1
fi

# Log file to store WordPress installation details
LOG_FILE="/root/wordpress-details.log"

# Start logging the OS detection process
{
    echo "WordPress Installation Started"
    echo "Operating System Detected: $OS_TYPE"
    echo ""
} > $LOG_FILE

# --- Add Firewall Rules for CentOS ONLY ---
if [ "$OS_TYPE" == "centos" ]; then
    {
        echo "[STEP EXTRA] Configuring firewall to allow HTTP and HTTPS..."
    } >> $LOG_FILE

    # Add firewalld rules for HTTP and HTTPS traffic
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https

    # Reload the firewall to apply the changes
    firewall-cmd --reload

    {
        echo "[STEP EXTRA] Firewall rules added and reloaded successfully."
        echo ""
    } >> $LOG_FILE
fi

### Begin process logging

# --- SYSTEM UPDATE ---
#{
#    echo "[STEP 1] Updating and upgrading the system..."
#} >> $LOG_FILE
#
#if [ "$OS_TYPE" == "debian" ]; then
#    export DEBIAN_FRONTEND=noninteractive
#    $PKG_MANAGER update -y >> /tmp/init-script.log
#    $PKG_MANAGER -y upgrade >> /tmp/init-script.log
#else
#    $PKG_MANAGER -y update >> /tmp/init-script.log
#    $PKG_MANAGER -y upgrade >> /tmp/init-script.log
#fi
#
#{
#    echo "[STEP 1] System update and upgrade completed."
#    echo ""
#} >> $LOG_FILE

# --- INSTALL APACHE ---
{
    echo "[STEP 2] Installing Apache..."
} >> $LOG_FILE

$PKG_MANAGER -y install $APACHE_SERVICE >> /tmp/init-script.log

{
    echo "[STEP 2] Apache installation completed."
    echo ""
} >> $LOG_FILE

# --- INSTALL MySQL/MariaDB ---
{
    echo "[STEP 3] Installing MySQL/MariaDB..."
} >> $LOG_FILE

if [ "$OS_TYPE" == "debian" ]; then
    debconf-set-selections <<< 'mysql-server mysql-server/root_password password rootpassword'
    debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password rootpassword'
    $PKG_MANAGER -y install mysql-server >> /tmp/init-script.log
else
    $PKG_MANAGER -y install mariadb-server mariadb >> /tmp/init-script.log
    systemctl start mariadb
    mysqladmin -u root password 'rootpassword'
fi

{
    echo "[STEP 3] MySQL/MariaDB installation completed."
    echo ""
} >> $LOG_FILE

# Secure MySQL installation
mysql -uroot -prootpassword <<SECURE_MYSQL
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
SECURE_MYSQL

# --- INSTALL PHP ---
{
    echo "[STEP 4] Installing PHP and PHP modules..."
} >> $LOG_FILE

$PKG_MANAGER install -y $PHP_PACKAGE >> /tmp/init-script.log

{
    echo "[STEP 4] PHP installation completed."
    echo ""
} >> $LOG_FILE

# --- ENABLE APACHE TO WORK WITH PHP ---
{
    echo "[STEP 5] Configuring and restarting Apache to work with PHP..."
} >> $LOG_FILE

if [ "$OS_TYPE" == "centos" ]; then
    # Enable and start Apache on CentOS
    systemctl enable $APACHE_SERVICE
    systemctl start $APACHE_SERVICE
    systemctl restart $APACHE_SERVICE
else
    # Restart Apache for Debian-based systems
    systemctl restart $APACHE_SERVICE
fi

{
    echo "[STEP 5] Apache restarted and configured with PHP."
    echo ""
} >> $LOG_FILE

# --- INSTALL WordPress ---
{
    echo "[STEP 6] Downloading and installing WordPress..."
} >> $LOG_FILE

cd /tmp
wget https://wordpress.org/latest.tar.gz
tar -xvzf latest.tar.gz >> /tmp/init-script.log
cp -R wordpress/* /var/www/html/

# Set ownership and permissions
chown -R www-data:www-data /var/www/html/
chmod -R 755 /var/www/html/

{
    echo "[STEP 6] WordPress files installed and permissions set."
    echo ""
} >> $LOG_FILE

# --- Configure MySQL for WordPress ---
{
    echo "[STEP 7] Configuring MySQL database for WordPress..."
} >> $LOG_FILE

WP_DB="wordpress_db" 
WP_USER="wp_user" 
WP_PASSWORD="wp_pass" 
mysql -uroot -prootpassword <<EOF
CREATE DATABASE $WP_DB;
CREATE USER '$WP_USER'@'localhost' IDENTIFIED BY '$WP_PASSWORD';
GRANT ALL PRIVILEGES ON $WP_DB.* TO '$WP_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

{
    echo "[STEP 7] MySQL database for WordPress has been created."
    echo ""
} >> $LOG_FILE

# --- Setup wp-config.php ---
{
    echo "[STEP 8] Configuring wp-config.php for WordPress..."
} >> $LOG_FILE

cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
sed -i "s/database_name_here/$WP_DB/" /var/www/html/wp-config.php
sed -i "s/username_here/$WP_USER/" /var/www/html/wp-config.php
sed -i "s/password_here/$WP_PASSWORD/" /var/www/html/wp-config.php

# Set Apache ownership and permissions after changes
chown -R www-data:www-data /var/www/html/
chmod -R 755 /var/www/html/

{
    echo "[STEP 8] wp-config.php configured successfully."
    echo ""
} >> $LOG_FILE

# --- Remove default Apache index.html ---
{
    echo "[STEP 9] Removing default Apache index.html..."
} >> $LOG_FILE

rm -f /var/www/html/index.html

{
    echo "[STEP 9] Default Apache index.html removed."
    echo ""
} >> $LOG_FILE

# --- Add a pause (sleep) before the Apache restart ---
#{
#    echo "[STEP 11] Pausing before restarting Apache..."
#} >> $LOG_FILE

sleep 5  # Adding a 5-second delay to give Apache a moment to settle

# --- Restart Apache to apply all changes ---
{
    echo "[STEP 10] Restarting Apache to apply changes..."
} >> $LOG_FILE

systemctl restart $APACHE_SERVICE

{
    echo "[STEP 10] Apache restarted. WordPress should now be accessible at the site's root URL."
    echo ""
} >> $LOG_FILE

# --- Generate WordPress Site Credentials ---
SITE_IP=$(hostname -I | awk '{print $1}')
ADMIN_URL="http://$SITE_IP/wp-admin"
SITE_URL="http://$SITE_IP"

# --- Save WordPress Details to Log File ---
{
    echo "==============================="
    echo "🎉 WordPress Installation Completed!"
    echo ""
    echo "Your WordPress site has been successfully installed, but you need to finalise the installation."
    echo ""
    echo "To complete the installation, visit the following URL:"
    echo "    $SITE_URL"
    echo "Then follow the instructions to set up your admin account and site."
    echo ""
    echo "==============================="
    echo "WordPress Setup Details"
    echo "==============================="
    echo "Site URL: $SITE_URL"
    echo "Admin Login URL: $ADMIN_URL"
    echo ""
    echo "Now go build an awesome website!"
} >> $LOG_FILE
