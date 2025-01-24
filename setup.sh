#!/bin/bash

info() {
  echo -e "\033[1;36m[INFO]\033[0m $1"
}

success() {
  echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
}

highlight() {
  echo -e "\033[1;34m$1\033[0m"
}

separator() {
  echo -e "\033[1;37m---------------------------------------------\033[0m"
}

clear

highlight "██╗    ██╗ █████╗ ██╗   ██╗███████╗███████╗"
highlight "██║    ██║██╔══██╗██║   ██║██╔════╝██╔════╝"
highlight "██║ █╗ ██║███████║██║   ██║█████╗  ███████╗"
highlight "██║███╗██║██╔══██║╚██╗ ██╔╝██╔══╝  ╚════██║"
highlight "╚███╔███╔╝██║  ██║ ╚████╔╝ ███████╗███████║██╗"
highlight " ╚══╝╚══╝ ╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚══════╝╚═╝"                                         

separator
info "Starting domain and SSL setup..."
separator

sudo apt update -y > /dev/null 2>&1
sudo apt install -y nodejs npm certbot python3-certbot-nginx nginx > /dev/null 2>&1
separator

info "Installing PM2..."
sudo npm install -g pm2 > /dev/null 2>&1
pm2 startup > /dev/null 2>&1
separator

info "Monitoring for domains..."
separator

VPS_IP=$(curl -s ifconfig.me)
MONITOR_LOG="/var/log/domain_monitor.log"

monitor_domains() {
  while true; do
    DOMAIN=$(dig -x $VPS_IP +short | grep -E '^[a-zA-Z0-9.-]+$' | head -n 1)

    if [ -n "$DOMAIN" ]; then
      info "Detected domain: $DOMAIN"
      
      info "Requesting SSL for $DOMAIN..."
      sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN --agree-tos --non-interactive --email admin@$DOMAIN > /dev/null 2>&1
      
      if [ $? -eq 0 ]; then
        success "SSL setup for $DOMAIN!"
        separator

        info "Setting up Nginx for $DOMAIN..."
        DhparamFile="/etc/ssl/certs/dhparam.pem"

        if [ ! -f "$DhparamFile" ]; then
          info "Generating Diffie-Hellman parameters..."
          sudo openssl dhparam -out $DhparamFile 2048 > /dev/null 2>&1
          success "Diffie-Hellman parameters created."
        fi

        cat <<EOF | sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_dhparam /etc/ssl/certs/dhparam.pem;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
        sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
        sudo nginx -t > /dev/null 2>&1

        if [ $? -eq 0 ]; then
          success "Nginx setup for $DOMAIN is valid. Reloading..."
          sudo systemctl reload nginx
          success "Nginx reloaded."
        else
          error "Nginx config for $DOMAIN invalid."
        fi
      else
        error "Failed SSL for $DOMAIN."
      fi
    else
      info "No domain found. Retrying..."
    fi
    sleep 10
  done
}

# Run monitor_domains directly without declare -f
nohup bash -c "monitor_domains" > $MONITOR_LOG 2>&1 &

info "Starting sample server with PM2..."
pm2 start index.mjs > /dev/null 2>&1
separator

success "🎉 Setup complete! Add domains pointing to $VPS_IP."
success "Monitoring for new domains 24/7."
separator