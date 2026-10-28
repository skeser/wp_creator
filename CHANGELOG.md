# Değişiklik geçmişi

## create (kurulum)

- **v1**: İlk sürüm. Liste dosyası parametreyle verilir (`data/`), sonuç dosyası `exec_result/<liste>_exec_result.txt` içine yazılır. Pool ve VirtualHost her çalışmada yeniden yazılır, diğer her şey yalnızca yoksa oluşturulur.

## destroy (geri alma)

- **v1**: İlk sürüm. VirtualHost, PHP-FPM havuzu, hosts satırı, veritabanı, MariaDB kullanıcıları ve Linux kullanıcısını siler.
- **v2**: `userdel` dönüş koduna takılıp betiğin durması düzeltildi.
- **v3**: PHP-FPM ve Apache her öğrenci için değil, sonda bir kez yeniden başlatılır (`start-limit-hit` hatası giderildi).
