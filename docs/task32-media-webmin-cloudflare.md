# №32 — Публикация Webmin медиасервера через Cloudflare Access

Единственный URL администратора дома: https://<site-id>-pve-mediaserver-admin.digitalhouses.vip/.
Для serzhan-home: https://serzhan-home-pve-mediaserver-admin.digitalhouses.vip/.

Применение выполняется отдельной задачей Semaphore №32; по умолчанию только audit.
Задача не создаёт туннели и политики Access, не изменяет учётные записи и не открывает Webmin в Интернет прямым пробросом порта.

Перед публикацией проверяются:
- Webmin на объявленном в приватном site-repo IPv4 медиасервера (HTTPS 10000).
- Существующий здоровый site PVE Tunnel с маршрутами PVE и FileBrowser.
- Действующее ограниченное Cloudflare Access приложение (точное или wildcard), email allow и отсутствие everyone/bypass.
- Отсутствие чужого DNS и ingress.
- Сохранение PVE TLS caPool, PVE и FileBrowser маршрутов и терминального 404.

При apply только добавляет HTTPS origin https://<media-ip>:10000
с noTLSVerify=true на приватном участке Tunnel → Webmin (самоподписанный
сертификат Webmin), отдельный CNAME,
а затем обязательно проверяет HTTP 302 в Cloudflare Access login.
Авторизация двухступенчатая: Cloudflare Access + Webmin.

Установка самого Webmin и групповая политика Samba принадлежат задаче №30.
После добавления третьего маршрута задача №10 допускает только строго
известный media-Webmin ingress как четвёртый элемент и не принимает чужие маршруты.
