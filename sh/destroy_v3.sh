#!/bin/bash
# =====================================================
# destroy.sh  -  create.sh ile yapılan kurulumu geri alır
# Sürüm : v3
# Dosya : destroy_v3.sh
#
# Değişiklik geçmişi:
#   v1  İlk sürüm. Listedeki öğrenciler için VirtualHost, PHP-FPM pool,
#       hosts satırı, veritabanı, MariaDB kullanıcıları ve Linux
#       kullanıcısını (ev dizini dahil) siler.
#   v2  userdel dönüş koduna takılıp durma hatası düzeltildi.
#   v3  PHP-FPM ve Apache her öğrenci için değil, sonda bir kez yeniden
#       başlatılır (systemd start-limit-hit hatası giderildi).
# =====================================================
set -euo pipefail

# ================== AYARLAR ==================
VERSION="v3"
DOMAIN="local"
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # wp_creator dizini
DATA_DIR="$BASE/data"
RESULT_DIR="$BASE/exec_result"
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

# --- Sonuç dosyası ---
LISTE_ADI="$(basename "$LISTE")"
LISTE_ADI="${LISTE_ADI%.txt}"
mkdir -p "$RESULT_DIR"
RAPOR="$RESULT_DIR/${LISTE_ADI}_destroy_exec_result.txt"
touch "$RAPOR"; chmod 600 "$RAPOR"
echo "# $SCRIPT_ADI sürüm $VERSION - $(date '+%Y-%m-%d %H:%M:%S')" >> "$RAPOR"

PHPV="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
FPM_SVC="php${PHPV}-fpm"

# --- Silinecek kullanıcıları topla ve onay iste ---
KULLANICILAR=()
while read -r U _; do
  U="${U%$'\r'}"
  [[ -z "${U:-}" || "$U" =~ ^# ]] && continue
  KULLANICILAR+=("$U")
done < "$LISTE"

if [ "${#KULLANICILAR[@]}" -eq 0 ]; then
  echo "Listede kullanıcı yok."; exit 1
fi

echo
echo "UYARI: Aşağıdaki öğrencilerin siteleri, dosyaları ve veritabanları SİLİNECEK (geri alınamaz):"
printf '   - %s\n' "${KULLANICILAR[@]}"
echo
read -r -p "Devam etmek için EVET yaz: " ONAY < /dev/tty
[ "$ONAY" = "EVET" ] || { echo "Vazgeçildi."; exit 1; }

# --- Her öğrenci için ---
for U in "${KULLANICILAR[@]}"; do
  H="/home/$U"; DB="wp_$U"; HOST="$U.$DOMAIN"
  POOL="/etc/php/$PHPV/fpm/pool.d/$U.conf"
  VHOST="/etc/apache2/sites-available/$U.conf"

  # Güvenlik: geçersiz ad ve sistem hesaplarını reddet
  if ! [[ "$U" =~ ^[a-z_][a-z0-9_-]*$ ]] || [[ "$U" =~ ^(root|www-data|mysql|daemon|bin|sys|nobody)$ ]]; then
    echo "[$U] geçersiz ya da korumalı ad, atlandı"; continue
  fi

  # Güvenlik: kullanıcı varsa, create.sh ile oluşturulmuş olmalı (ogrenciler grubunda)
  if id "$U" &>/dev/null; then
    if ! id -nG "$U" | tr ' ' '\n' | grep -qx "ogrenciler"; then
      echo "[$U] 'ogrenciler' grubunda değil, create.sh ile oluşturulmamış, atlandı"; continue
    fi
  fi

  echo "[$U] siliniyor..."

  # Apache VirtualHost
  a2dissite "$U" >/dev/null 2>&1 || true
  rm -f "$VHOST"
  rm -f "/var/log/apache2/$U-error.log" "/var/log/apache2/$U-access.log"

  # PHP-FPM pool
  rm -f "$POOL"

  # Sunucunun hosts dosyasındaki satır
  HOST_RE="${HOST//./\\.}"
  sed -i "/^127\.0\.0\.1[[:space:]]\+${HOST_RE}[[:space:]]*\$/d" /etc/hosts

  # Veritabanı ve MariaDB kullanıcıları
  mariadb -e "DROP DATABASE IF EXISTS \`$DB\`;
DROP USER IF EXISTS '$DB'@'localhost';
DROP USER IF EXISTS '$U'@'localhost';
FLUSH PRIVILEGES;"

  # Linux kullanıcısı (userdel dönüş kodu önemsenmez, sonucu id ile kontrol edilir)
  if id "$U" &>/dev/null; then
    pkill -KILL -u "$U" 2>/dev/null || true
    gpasswd -d www-data "$U" >/dev/null 2>&1 || true
    userdel -r "$U" >/dev/null 2>&1 || true
    if id "$U" &>/dev/null; then
      echo "    ! Linux kullanıcısı silinemedi: $U"
    fi
  fi

  # Ev dizini (userdel -r silemediyse)
  [ -d "$H" ] && rm -rf "$H"

  # Kalan grup
  if getent group "$U" >/dev/null; then
    groupdel "$U" 2>/dev/null || true
  fi

  echo "$U  silindi" >> "$RAPOR"
done

# --- Servisleri bir kez yeniden başlat ---
echo "Servisler yeniden başlatılıyor..."
systemctl reset-failed "$FPM_SVC" 2>/dev/null || true
systemctl restart "$FPM_SVC"
apache2ctl configtest
systemctl reload apache2

echo "Bitti ($SCRIPT_ADI $VERSION). Özet: $RAPOR"
