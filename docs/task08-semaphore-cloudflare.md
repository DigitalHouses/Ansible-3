# №08 — Semaphore и Cloudflare Access

## Схема (07.11.2026)

- **LAN:** `http://<runner-ip>/`; для serzhan-home это `http://192.168.11.231/`.
- **Единственный нативный Semaphore:** HTTP на порту `80`, `web_host: ""`.
  Никакого локального TLS, доверенных сертификатов Windows или отдельного nginx.
- **Внешний доступ:** `https://<site-id>-pve-semaphore.digitalhouses.vip/`
  через выделенный Cloudflare Tunnel и существующий Cloudflare Access.
- **Cloudflare origin:** `http://127.0.0.1:80` внутри Runner, не публичный HTTP.
  Остальные публичные hostname, DNS и Access policy не изменяются.
- **Runner и DEV API:** `http://127.0.0.1/api` и
  `http://<runner-ip>/api` соответственно. DEV использует защищённый
  revocable API-токен, передаваемый по действующему пути №08.
- Токены Cloudflare выдаются штатной задачей №05; запуск №08 не создаёт
  дополнительного пользователя, не пересоздаёт Tunnel и не требует пароля TLS.

Bootstrap, №00, №05 и №08 используют ту же простую схему HTTP 80.
Для Semaphore 2.20.16-beta9 `web_host: "/"` ломает кнопку Raw Log:
frontend объединяет `"/"` и `"/api/..."`, получая `//api/...`, что браузер
интерпретирует как хост `api`. Пустой `web_host` сохраняет
`<base href="/">`, а Raw Log направляет запрос на текущий origin.
Повторный №08 проверяет base href для LAN и CF.
Если `web_host` надо исправить, существующий рестарт Semaphore
откладывается до выхода из исполняемой задачи.

## Миграция действующего узла

Одноразовая миграция выполнена Semaphore task `#87`, status `success`.
Владение Tunnel, старый ingress, состояние локального HTTPS и доступность
порта 80 проверены перед изменением. Сохранена root-only копия старого
`/etc/semaphore/config.json` на случай отката. После перенастройки origin
служба Semaphore перезапущена штатно на `:80`. Временный шаблон и временный
репозиторий Semaphore удалены.

Проверено из центрального DEV: `GET http://192.168.11.231/api/ping`
— HTTP 200, `GET /` — HTTP 200, авторизованный DEV API `/api/user/`
— успешен; внешний CF HTTPS продолжает переводить неавторизованного клиента
на Access login (HTTP 302).

Локальный HTTP передаёт авторизацию в пределах домашней сети без TLS.
Публичный интернет-доступ остаётся только через Cloudflare HTTPS/Access.
