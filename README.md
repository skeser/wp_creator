# wp_creator

Debian sunucuda, bir sınıftaki her öğrenci için **izole bir WordPress sitesi** kuran ve gerektiğinde hepsini **tek komutla geri silen** bash betikleri.

Okul / laboratuvar gibi **yerel ağlarda** (DNS sunucusuna erişimin olmadığı ortamlarda da) çalışacak şekilde hazırlandı. Öğrenciler sitelerine kendi bilgisayarlarındaki `hosts` dosyası üzerinden ulaşır.

> ⚠️ Bu proje internete açık sunucular için **tasarlanmadı**. Ayrıntılar için [Güvenlik notları](#güvenlik-notları) bölümüne bak.

## İçindekiler

- [Ne yapar?](#ne-yapar)
- [Gereksinimler](#gereksinimler)
- [Klasör yapısı](#klasör-yapısı)
- [Hızlı başlangıç](#hızlı-başlangıç)
- [Liste dosyası biçimi](#liste-dosyası-biçimi)
- [Betikler](#betikler)
- [Öğrenci bilgisayarları](#öğrenci-bilgisayarları)
- [Tekrar çalıştırma davranışı](#tekrar-çalıştırma-davranışı)
- [Güvenlik notları](#güvenlik-notları)
- [Sorun giderme](#sorun-giderme)
- [Lisans](#lisans)

## Ne yapar?

Listedeki her öğrenci için şunları oluşturur:

| Kaynak | Ayrıntı |
|---|---|
| Linux kullanıcısı | `kullanici` (kabuk erişimi yok, `nologin`) |
| Site dizini | `/home/kullanici/public_html` |
| Site adresi | `http://kullanici.local` |
| PHP-FPM havuzu | Öğrencinin kendi kullanıcısıyla çalışır, `open_basedir` ve ayrı `tmp` dizini ile kısıtlıdır |
| Apache VirtualHost | Öğrenciye özel, ayrı log dosyaları |
| Veritabanı | `wp_kullanici` |
| MariaDB kullanıcıları | `wp_kullanici` (WordPress için) ve `kullanici` (öğrencinin veritabanı aracıyla girişi için). İkisi de **sadece kendi veritabanını** görür |
| WordPress | Türkçe paket, `wp-config.php` hazır geldiği için öğrenci yalnızca kurulum sihirbazını tamamlar |
| SFTP | `ChrootDirectory` ile öğrenci sadece kendi dizinini görür |

Öğrencilerin PHP kodları kendi Linux kullanıcılarıyla çalıştığı için biri diğerinin dosyalarını (ör. `wp-config.php`) okuyamaz.

## Gereksinimler

- Debian 13 (PHP 8.4, Apache 2.4, MariaDB ile denendi). Diğer Debian/Ubuntu sürümlerinde de çalışması beklenir ancak test edilmedi.
- `root` yetkisi
- **Apache 2.4 önceden kurulu** olmalı (`apt install apache2`). Betik Apache'yi kurmaz, MariaDB ve PHP-FPM'i kurar.
- WordPress paketini indirmek için internet erişimi (ilk çalıştırmada bir kez)
- SFTP için çalışan OpenSSH sunucusu

## Klasör yapısı

```
wp_creator/
├── sh/
│   ├── create_v1.sh     # kurulum
│   └── destroy_v3.sh    # geri alma (silme)
├── data/
│   └── sinif1.example.txt   # örnek liste (kendi listelerin buraya gelir)
└── exec_result/             # betiklerin ürettiği sonuç dosyaları
```

`data/*.txt` (örnek dosya hariç) ve `exec_result/` içeriği `.gitignore` ile repoya **alınmaz**, çünkü öğrenci adları ve şifreleri içerir.

## Hızlı başlangıç

```bash
git clone https://github.com/KULLANICI/wp_creator.git /root/wp_creator
cd /root/wp_creator

# 1. Liste dosyanı oluştur
cp data/sinif1.example.txt data/sinif1.txt
nano data/sinif1.txt

# 2. Kur
cd sh
bash create_v1.sh sinif1.txt
```

Kurulumdan sonra her öğrenci tarayıcıdan `http://kullanici.local` adresini açıp WordPress kurulum sihirbazını tamamlar.

## Liste dosyası biçimi

Her satır `kullanıcı_adı  şifre` biçimindedir (boşlukla ayrılır). `#` ile başlayan satırlar ve boş satırlar yok sayılır.

```
# sinif1.txt
ogrenci1   Sifre-Ornek-1
ogrenci2   Sifre-Ornek-2
```

Kurallar:

- Kullanıcı adı **küçük harf, rakam, `_` ve `-`** içermelidir (silme betiği başka adları reddeder).
- Şifrede **boşluk, `'` (tek tırnak) ve `\` (ters eğik çizgi)** olmamalıdır. Bu karakterleri içeren satır uyarıyla atlanır.
- Aynı şifre hem Linux (SFTP) hem MariaDB hesaplarında kullanılır.
- Dosya Windows'ta hazırlanmışsa satır sonu (CRLF) betik tarafından otomatik temizlenir.

## Betikler

İki betik de `sh/` klasöründen çalıştırılır ve `root` gerektirir. Liste dosyası adını verirsen `data/` içinde arar, tam yol da verebilirsin.

### `create_v1.sh`: kurulum

```bash
bash create_v1.sh sinif1.txt
bash create_v1.sh /baska/yer/liste.txt
```

Sonuç dosyası: `exec_result/sinif1_exec_result.txt` (o çalışmada **yeni** oluşturulan öğrencilerin site ve veritabanı kullanıcı adları; şifre içermez).

### `destroy_v3.sh`: geri alma

`create` ile kurulanları aynı listeyle siler. Çalışmadan önce silinecek kullanıcıları gösterir ve `EVET` yazmanı bekler.

```bash
bash destroy_v3.sh sinif1.txt
```

Siler: VirtualHost ve log dosyaları, PHP-FPM havuzu, sunucudaki `hosts` satırı, veritabanı, iki MariaDB kullanıcısı (yetkileriyle birlikte), Linux kullanıcısı ve **ev dizini (tüm site dosyaları)**.

Silmez (tüm sınıflar için ortak olduğundan): `ogrenciler` grubu, `sshd_config` içindeki SFTP kuralı, indirilmiş WordPress paketi, kurulu paketler.

Güvenlik önlemleri: `ogrenciler` grubunda olmayan kullanıcılar, `root`/`www-data` gibi sistem adları ve geçersiz adlar atlanır. Sonuç dosyası: `exec_result/sinif1_destroy_exec_result.txt`.

> Silme **geri alınamaz**. Gerekirse önce `/home/kullanici/public_html` ve veritabanlarını yedekle (`mariadb-dump wp_kullanici > yedek.sql`).

## Öğrenci bilgisayarları

DNS sunucusu olmadığı için her öğrenci kendi bilgisayarında `hosts` dosyasına bir satır ekler (`SUNUCU_IP` yerine sunucunun IP adresi):

```
SUNUCU_IP   ogrenci1.local
```

| İşletim sistemi | Dosya | Not |
|---|---|---|
| Windows | `C:\Windows\System32\drivers\etc\hosts` | Not Defteri'ni **yönetici olarak** aç |
| Linux / macOS | `/etc/hosts` | `sudo` ile düzenle |

Dosya aktarımı (SFTP): FileZilla ya da WinSCP ile `SUNUCU_IP`, port `22`, kullanıcı `kullanici`. Bağlanınca yalnızca `public_html` ve `tmp` klasörleri görünür.

## Tekrar çalıştırma davranışı

`create_v1.sh` birden fazla kez çalıştırılabilir: listeye yeni öğrenci ekleyip komutu tekrar çalıştırman yeterli. Var olan hiçbir şeyin üzerine yazılmaz, tek istisna aşağıdaki iki dosya türüdür.

| Öğe | Her çalışmada |
|---|---|
| PHP-FPM havuzu (`pool.d/kullanici.conf`) | **yeniden yazılır** |
| Öğrenci VirtualHost'u | **yeniden yazılır** |
| Linux kullanıcısı, şifre, dizin izinleri | sadece yeni kullanıcıda |
| WordPress dosyaları, `wp-config.php` | sadece yoksa |
| Veritabanı ve MariaDB kullanıcıları | sadece yoksa (şifre değişmez) |
| `hosts` satırı, SFTP kuralı | sadece yoksa eklenir |

Havuz ve VirtualHost ayarlarını kalıcı olarak değiştirmek istiyorsan betiğin içinden değiştir. Var olan bir öğrencinin şifresini değiştirmek için `passwd` ve `ALTER USER` komutlarını elle kullan.

## Güvenlik notları

- **Sadece güvenilen yerel ağda kullan.** Siteler HTTP (şifresiz) çalışır. SSH/SFTP ve MariaDB portlarını internete açma.
- Şifreler liste dosyasında **düz metin** olarak durur. `data/*.txt` dosyalarını repoya yükleme (`.gitignore` bunu engeller), işin bitince `shred -u data/sinif1.txt` ile sil.
- Aynı şifre Linux ve MariaDB hesaplarında kullanıldığı için **güçlü ve öğrenciye özel** şifreler seç. Sadece rakamdan oluşan kısa şifreler zayıftır.
- Öğrencilerin PHP'sinde `exec`, `system`, `shell_exec` gibi fonksiyonlar kapatılmıştır. Bu bir **kum havuzu garantisi değildir**; kötü niyetli kullanıcılara karşı ek önlem gerekir.
- Betik `/etc/ssh/sshd_config` dosyasına `Match Group ogrenciler` bloğu ekler ve `ssh`, `apache2`, `php-fpm` servislerini yeniden başlatır. Çalıştırmadan önce açık bir ikinci oturum bulundur.
- `.local` uzantısı mDNS için ayrılmıştır. Windows'ta `hosts` dosyası öncelikli olduğu için sorun çıkmaz, Linux/macOS istemcilerde çözümleme yavaşlarsa `create_v1.sh` içindeki `DOMAIN` değişkenini (ör. `lan`, `test`) değiştir. `destroy` betiğinde de aynı değeri kullan.

## Sorun giderme

| Belirti | Neden / Çözüm |
|---|---|
| `: invalid option name` / `pipefail` hatası | Betik Windows satır sonlarıyla (CRLF) kaydedilmiş. `sed -i 's/\r$//' dosya.sh` çalıştır. Repoda `.gitattributes` bunu önler. |
| `Service Unavailable` (Apache) | PHP-FPM soketine ulaşılamıyor. `ls /run/php/` ile soketi, `systemctl status php8.x-fpm` ile servisi kontrol et. |
| `start-limit-hit` (php-fpm) | Servis kısa sürede çok kez yeniden başlatıldı. `systemctl reset-failed php8.x-fpm && systemctl start php8.x-fpm`. |
| WordPress: `Veri tabanı bağlantısı kurulurken sorun çıktı` | `grep -E "DB_(NAME\|USER\|PASSWORD)" /home/KULLANICI/public_html/wp-config.php` ile bilgileri, `mariadb -u wp_KULLANICI -p` ile girişi doğrula. |
| SFTP bağlanıyor ama dizin boş / hata | `ChrootDirectory` için `/home/kullanici` dizini `root` sahipli ve grup/diğerleri tarafından yazılamaz olmalıdır. |

## Sürümler

Betik dosya adları ve içindeki `VERSION` değişkeni sürümü gösterir. Ayrıntı için [CHANGELOG.md](CHANGELOG.md).

## Lisans

[MIT](LICENSE)
