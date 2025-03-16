#!/bin/bash

# Fungsi untuk menghasilkan password acak
generate_password() {
  openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12
}

# Fungsi untuk validasi username
validate_username() {
  while true; do
    read -p "Masukkan username baru: " namauser
    if id "$namauser" &>/dev/null; then
      echo "Username sudah ada. Silakan coba lagi."
    else
      break
    fi
  done
}

# Fungsi untuk validasi domain
validate_domain() {
  while true; do
    read -p "Masukkan nama domain: " namadomain
    if [ -f /etc/nginx/sites-available/"$namadomain" ]; then
      echo "Domain sudah ada dalam konfigurasi Nginx. Silakan coba lagi."
      continue
    fi

    server_ip=$(curl -s icanhazip.com)
    domain_ip=$(host "$namadomain" 2>/dev/null | grep "has address" | awk '{print $4}')

    if [ -z "$domain_ip" ]; then
      echo "Domain tidak ditemukan dalam DNS. Silakan periksa konfigurasi domain Anda."
      continue
    fi

    if [ "$server_ip" != "$domain_ip" ]; then
      echo "Domain tidak mengarah ke IP server ini. Silakan periksa DNS Anda."
      continue
    fi

    break
  done
}

# Fungsi untuk membuat user
create_user() {
  echo "Membuat user $namauser..."
  if sudo useradd -m -d /var/www/"$namauser" -s /bin/bash "$namauser"; then
    sudo mkdir -p /var/www/"$namauser"/public_html
    sudo cp -r /software/wordpress/* /var/www/"$namauser"/public_html
    sudo chown -R "$namauser":"$namauser" /var/www/"$namauser"
    sudo chmod 755 /var/www/"$namauser"
    sudo chmod 750 /var/www/"$namauser"/public_html
    echo "$namauser:$password" | sudo chpasswd
    sudo setfacl -m u:www-data:x /var/www/"$namauser"
    sudo setfacl -R -m u:www-data:rx /var/www/"$namauser"/public_html
    sudo setfacl -d -m u:www-data:rx /var/www/"$namauser"/public_html
    echo "User $namauser berhasil dibuat."
  else
    echo "Gagal membuat user. Silakan periksa log sistem."
    exit 1
  fi
}

# Fungsi untuk membuat VHOST Nginx
create_vhost() {
  echo "Membuat konfigurasi VHOST untuk $namadomain..."
  cat <<EOF | sudo tee /etc/nginx/sites-available/"$namadomain" > /dev/null
server {
    listen 80;
    server_name $namadomain;
    root /var/www/$namauser/public_html;
    index index.php index.html index.htm;

    access_log /var/log/nginx/${namadomain}_access.log;
    error_log /var/log/nginx/${namadomain}_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~* \.(?:ico|css|js|gif|jpe?g|png|woff2?|eot|ttf|otf|svg|mp4|webp)$ {
        expires 6M;
        access_log off;
        add_header Cache-Control "public, max-age=15552000, immutable";
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        include snippets/php8.3-fpm.conf;
    }

    location ~ /\. {
        deny all;
    }
}
EOF

  sudo ln -sf /etc/nginx/sites-available/"$namadomain" /etc/nginx/sites-enabled/
  if sudo nginx -t && sudo systemctl reload nginx; then
    echo "Konfigurasi VHOST untuk $namadomain berhasil dibuat."
  else
    echo "Konfigurasi Nginx gagal! Silakan periksa log error."
    exit 1
  fi
}

# Fungsi untuk instalasi SSL dengan Certbot
install_ssl() {
  read -p "Apakah Anda ingin menginstal SSL dengan Certbot? (y/n): " ssl_choice
  if [[ "$ssl_choice" == "y" ]]; then
    if ! command -v certbot &>/dev/null; then
      echo "Certbot tidak terinstal. Menginstal Certbot..."
      sudo apt update && sudo apt install -y certbot python3-certbot-nginx
    fi

    while true; do
      echo "Memulai instalasi SSL dengan Certbot..."
      if sudo certbot --nginx -d "$namadomain"; then
        echo "Instalasi SSL berhasil."
        break
      else
        echo "Gagal menginstal SSL! Silakan periksa log Certbot."
        read -p "Coba lagi? (y/n): " retry_ssl
        if [[ "$retry_ssl" != "y" ]]; then
          echo "SSL tidak diinstal."
          break
        fi
      fi
    done
  fi
}

# Mulai proses
validate_username

# Pilihan password
read -p "Pilih opsi password: (1) Generate otomatis, (2) Input manual: " password_option
if [[ "$password_option" == "1" ]]; then
  password=$(generate_password)
else
  while true; do
    read -sp "Masukkan password (minimal 8 karakter): " password
    echo ""
    if [[ ${#password} -ge 8 ]]; then
      break
    else
      echo "Password terlalu pendek. Minimal 8 karakter."
    fi
  done
fi

validate_domain
create_user
create_vhost
install_ssl

# Informasi kepada pengguna
echo "Username: $namauser"
echo "Password: $password"
echo "Website: $namadomain"
echo "Simpan informasi akun ini dengan aman."
echo "Selesai."
