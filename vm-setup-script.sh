#!/bin/bash

apt-get update
apt-get upgrade -y
apt-get install -y nginx 

cat << 'EOT' > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head>
    <title>Web Server</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            display: flex; 
            justify-content: center; 
            align-items: center; 
            height: 100vh; 
            margin: 0; 
            background-color: #f0f0f0; 
        }
        .message { 
            font-size: 24px; 
            text-align: center; 
            padding: 20px; 
            background-color: white; 
            border-radius: 10px; 
            box-shadow: 0 4px 6px rgba(0,0,0,0.1); 
        }
    </style>
</head>
<body>
    <div class="message">
        Welcome to Web Server ${SERVER_NUMBER} ${REGION} Region
    </div>
</body>
</html>
EOT

# Konfigurasi nginx untuk menggunakan custom HTML
cat << 'EOT' > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOT

ufw allow 80/tcp
ufw enable

# Restart nginx untuk apply perubahan
systemctl restart nginx

