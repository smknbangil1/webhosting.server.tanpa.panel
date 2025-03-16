#!/bin/bash

LOGFILE="/var/log/vhost_creation.log"

# Fungsi untuk menampilkan pesan error dan keluar
error_exit() {
  echo "Error: $1"
  echo "$(date) - ERROR: $1" >> "$LOGFILE"
  exit 1
}

echo "$(date) - Memulai proses pembuatan vhost" >> "$LOGFILE"

# 1. Input Nama Pengguna
while true; do
  read -p "Masukkan nama pengguna: " namauser
  if [[ ! "$namauser" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "Nama pengguna tidak valid. Gunakan huruf, angka, titik, underscore, atau tanda hubung."
    continue
  fi
  if id "$namauser" >/dev/null 2>&1; then
    break
  else
    echo "Pengguna '$namauser' tidak ditemukan. Coba lagi."
  fi
done

# 2. Input Domain/Subdomain
while true; do
  read -p "Masukkan domain/subdomain: " domain
  if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "Domain tidak valid. Gunakan format yang benar (contoh: example.com atau sub.example.com)."
    continue
  fi
  if nginx -T 2>&1 | grep -q "server_name $domain"; then
    echo "Domain '$domain' sudah ada. Coba lagi."
  else
    break
  fi
done

# 3. Buat Direktori
direktori="/var/www/$namauser/$domain"
mkdir -p "$direktori" || error_exit "Gagal membuat direktori $direktori"
echo "Direktori $direktori berhasil dibuat."

# 4. Salin File Index
cp /software/index.html "$direktori/index.html" || error_exit "Gagal menyalin file index.html"
echo "File index.html berhasil disalin."

# 5. Atur Kepemilikan dan Hak Akses
chown -R "$namauser:$namauser" "$direktori" || error_exit "Gagal mengubah kepemilikan direktori"
chmod -R 750 "$direktori" || error_exit "Gagal mengubah hak akses direktori"

# Atur ACL untuk www-data
setfacl -R -m u:www-data:rx "$direktori" || error_exit "Gagal mengatur ACL (rx untuk www-data)"
setfacl -d -m u:www-data:rx "$direktori" || error_exit "Gagal mengatur ACL default (rx untuk www-data)"
echo "ACL berhasil dikonfigurasi."

# 6. Buat Konfigurasi Vhost Nginx
konfigurasi_vhost="/etc/nginx/sites-available/$domain"
cat <<EOF > "$konfigurasi_vhost"
server {
    listen 80;
    server_name $domain;
    root $direktori;
    index index.php index.html index.htm;

    # Log files
    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log warn;

    # Cache static files
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg|eot|mp4|webm|ogg|zip|tar|gz|bz2|rar|7z)$ {
        expires max;
        log_not_found off;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    # Handle requests
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # PHP Processing
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        include snippets/php8.3-fpm.conf;
    }

    # Deny access to Apache leftovers
    location ~ /\.ht {
        deny all;
    }
}
EOF

if [ $? -ne 0 ]; then
  error_exit "Gagal membuat konfigurasi vhost Nginx"
fi

ln -s "$konfigurasi_vhost" "/etc/nginx/sites-enabled/$domain" || error_exit "Gagal membuat symbolic link"
echo "Konfigurasi vhost Nginx berhasil dibuat."

# 7. Uji Konfigurasi Nginx
nginx -t || error_exit "Konfigurasi Nginx tidak valid"
systemctl reload nginx || error_exit "Gagal me-reload Nginx"
echo "Konfigurasi Nginx berhasil diuji dan direload."

sleep 1

# 8. Buat Sertifikat SSL (Opsional)
read -p "Instal sertifikat SSL? (y/n): " install_ssl
if [[ "$install_ssl" == "y" ]]; then
  if ! command -v certbot &>/dev/null; then
    echo "Certbot tidak ditemukan! Silakan instal certbot terlebih dahulu."
    exit 1
  fi
  certbot --nginx -d "$domain"
  if [ $? -ne 0 ]; then
    echo "Pembuatan sertifikat SSL gagal. Silakan periksa log Certbot."
  else
    echo "Sertifikat SSL berhasil dibuat."
  fi
fi

# 9. Tampilkan Hasil Akhir
echo "Vhost '$domain' berhasil dibuat."
if [[ "$install_ssl" == "y" ]]; then
  echo "Sertifikat SSL berhasil dibuat dan diinstal."
fi
echo "Layanan web '$domain' aktif."
echo "$(date) - Vhost '$domain' berhasil dibuat oleh user '$namauser'." >> "$LOGFILE"
