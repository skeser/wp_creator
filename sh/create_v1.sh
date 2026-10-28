#!/bin/bash
# =====================================================
# create.sh  -  Öğrenci WordPress kurulum betiği
# Sürüm : v1
# Dosya : create_v1.sh
#
# Değişiklik geçmişi:
#   v1  İlk sürüm. Liste dosyası parametreyle verilir (data/),
#       sonuç dosyası exec_result/<liste>_exec_result.txt içine yazılır.
# =====================================================
set -euo pipefail

# ================== AYARLAR ==================
VERSION="v1"
DOMAIN="local"
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # wp_creator dizini
DATA_DIR="$BASE/data"
RESULT_DIR="$BASE/exec_result"
WP_DIR="/usr/local/src/wordpress"
SCRIPT_ADI="$(basename "$0")"
# =============================================

echo "== $SCRIPT_ADI (sürüm $VERSION) =="

[ "$(id -u)" -eq 0 ] || { echo "root olarak çalıştır"; exit 1; }

# --- Liste dosyası parametresi ---
if [ $# -ne 1 ]; then
  echo "Kullanım: bash $SCRIPT_ADI <liste.txt>"
  echo "Örnek:    bash $SCRIPT_ADI sinif1.txt   ($DATA_DIR altında aranır)"
  exit 1
fi
if [ -f "$1" ]; then
  LISTE="$1"
elif [ -f "$DATA_DIR/$1" ]; then
  LISTE="$DATA_DIR/$1"
else
  echo "Liste dosyası bulunamadı: $1"
  echo "Aranan yerler: $1 ve $DATA_DIR/$1"
  exit 1
fi
echo "Liste: $LISTE"
sed -i 's/\r$//' "$LISTE" 2>/dev/null || true

# --- Sonuç dosyası: wp_creator/exec_result/<liste_adi>_exec_result.txt ---
LISTE_ADI="$(basename "$LISTE")"
LISTE_ADI="${LISTE_ADI%.txt}"
mkdir -p "$RESULT_DIR"
RAPOR="$RESULT_DIR/${LISTE_ADI}_exec_result.txt"
touch "$RAPOR"; chmod 600 "$RAPOR"
echo "# $SCRIPT_ADI sürüm $VERSION - $(date '+%Y-%m-%d %H:%M:%S')" >> "$RAPOR"
echo "Sonuç dosyası: $RAPOR"

# --- Paketler ve modüller ---
apt-get install -y curl openssl mariadb-server php-fpm php-mysql php-curl php-gd \
  php-mbstring php-xml php-zip php-intl >/dev/null
a2enmod proxy_fcgi setenvif rewrite >/dev/null

PHPV="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
FPM_SVC="php${PHPV}-fpm"
echo "PHP sürümü: $PHPV"

# --- WordPress paketi (bir kez) ---
if [ ! -f "$WP_DIR/wp-settings.php" ]; then
  mkdir -p "$WP_DIR"
  curl -fsSL https://tr.wordpress.org/latest-tr_TR.tar.gz | tar xz -C "$WP_DIR" --strip-components=1
fi

# --- SFTP grubu ve chroot (yoksa ekler) ---
getent group ogrenciler >/dev/null || groupadd ogrenciler
if ! grep -q "^Match Group ogrenciler" /etc/ssh/sshd_config; then
cat >> /etc/ssh/sshd_config <<'SSHEOF'

Match Group ogrenciler
    ChrootDirectory /home/%u
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PasswordAuthentication yes
SSHEOF
fi

# --- Her öğrenci için ---
while read -r U P _; do
  U="${U%$'\r'}"; P="${P%$'\r'}"
  [[ -z "${U:-}" || "$U" =~ ^# ]] && continue
  if [[ "$P" == *"'"* || "$P" == *'\'* ]]; then
    echo "[$U] şifrede ' veya \\ olamaz, atlandı"; continue
  fi

  H="/home/$U"; DB="wp_$U"; HOST="$U.$DOMAIN"
  CFG="$H/public_html/wp-config.php"
  POOL="/etc/php/$PHPV/fpm/pool.d/$U.conf"
  VHOST="/etc/apache2/sites-available/$U.conf"
  echo "[$U] kontrol ediliyor..."

  # Linux kullanıcısı: sadece yoksa oluştur, şifre ve izinler sadece o zaman ayarlanır
  if ! id "$U" &>/dev/null; then
    echo "    + Linux kullanıcısı oluşturuluyor"
    useradd -m -s /usr/sbin/nologin -G ogrenciler "$U"
    usermod -aG "$U" www-data
    echo "$U:$P" | chpasswd
    chown root:"$U" "$H"; chmod 750 "$H"
    echo "$U  site=http://$HOST  db=$DB  dbuser=$DB ve $U" >> "$RAPOR"
  fi

  # Dizinler: yoksa oluştur
  if [ ! -d "$H/public_html" ]; then
    mkdir -p "$H/public_html"; chown "$U:$U" "$H/public_html"
  fi
  if [ ! -d "$H/tmp" ]; then
    mkdir -p "$H/tmp"; chown "$U:$U" "$H/tmp"; chmod 700 "$H/tmp"
  fi

  # PHP-FPM pool: her çalışmada yeniden yazılır
  cat > "$POOL" <<POOLEOF
[$U]
user = $U
group = $U
listen = /run/php/$U.sock
listen.owner = www-data
listen.group = www-data
pm = ondemand
pm.max_children = 5
pm.process_idle_timeout = 20s
php_admin_value[open_basedir] = $H/public_html:$H/tmp:/usr/share/php
php_admin_value[upload_tmp_dir] = $H/tmp
php_admin_value[sys_temp_dir] = $H/tmp
php_admin_value[session.save_path] = $H/tmp
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen
POOLEOF

  # Apache VirtualHost: her çalışmada yeniden yazılır
  cat > "$VHOST" <<VHEOF
<VirtualHost *:80>
    ServerName $HOST
    DocumentRoot $H/public_html
    <Directory $H/public_html>
        AllowOverride All
        Require all granted
    </Directory>
    <FilesMatch \.php\$>
        SetHandler "proxy:unix:/run/php/$U.sock|fcgi://localhost"
    </FilesMatch>
    ErrorLog \${APACHE_LOG_DIR}/$U-error.log
    CustomLog \${APACHE_LOG_DIR}/$U-access.log combined
</VirtualHost>
VHEOF
  a2ensite "$U" >/dev/null

  # Sunucunun hosts dosyası: satır yoksa ekle
  grep -qw "$HOST" /etc/hosts || echo "127.0.0.1 $HOST" >> /etc/hosts

  # WordPress dosyaları: sadece boşsa kopyala
  if [ ! -f "$H/public_html/wp-settings.php" ]; then
    echo "    + WordPress kopyalanıyor"
    cp -a "$WP_DIR/." "$H/public_html/"
    chown -R "$U:$U" "$H/public_html"
  fi

  # wp-config.php: sadece yoksa oluştur (DB bilgileri ve salt bu sırada yazılır)
  if [ ! -f "$CFG" ]; then
    echo "    + wp-config.php oluşturuluyor"
    cp "$H/public_html/wp-config-sample.php" "$CFG"
    PE="$(printf '%s' "$P" | sed 's/[\/&]/\\&/g')"
    sed -i "s/^define( *'DB_NAME'.*/define( 'DB_NAME', '$DB' );/" "$CFG"
    sed -i "s/^define( *'DB_USER'.*/define( 'DB_USER', '$DB' );/" "$CFG"
    sed -i "s/^define( *'DB_PASSWORD'.*/define( 'DB_PASSWORD', '$PE' );/" "$CFG"
    sed -i "s/^define( *'DB_HOST'.*/define( 'DB_HOST', 'localhost' );/" "$CFG"
    for K in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
      S="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 64)"
      sed -i "s/define( *'$K'.*/define( '$K', '$S' );/" "$CFG"
    done
    chown "$U:$U" "$CFG"; chmod 640 "$CFG"
  fi

  # Veritabanı ve kullanıcılar: yoksa oluştur (var olanın şifresi değişmez)
  mariadb -e "CREATE DATABASE IF NOT EXISTS \`$DB\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB'@'localhost' IDENTIFIED BY '$P';
GRANT ALL PRIVILEGES ON \`$DB\`.* TO '$DB'@'localhost';
CREATE USER IF NOT EXISTS '$U'@'localhost' IDENTIFIED BY '$P';
GRANT ALL PRIVILEGES ON \`$DB\`.* TO '$U'@'localhost';
FLUSH PRIVILEGES;"
done < "$LISTE"

# --- Servisleri yeniden başlat ---
sshd -t && systemctl restart ssh
systemctl restart "$FPM_SVC"
apache2ctl configtest
systemctl restart apache2

echo "Bitti ($SCRIPT_ADI $VERSION). Özet: $RAPOR"
