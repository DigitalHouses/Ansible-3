# №08 — Semaphore и Cloudflare Access

Веб-доступ к Semaphore на сервере Runner через выделенный Cloudflare Tunnel
`<site-id>-semaphore` и адрес `https://<site-id>-semaphore.digitalhouses.vip/`.
Это продолжение существующей задачи №08 (DEV ↔ Semaphore), а не №10 PVE.

- Источник: `https://127.0.0.1:3000` непосредственно в Runner LXC.
- Origin TLS проверяется с `/etc/semaphore/tls.crt` (`noTLSVerify=false`).
- Требуется уже существующая защищённая Cloudflare Access политика
  для `*.digitalhouses.vip` или точного hostname. Без неё DNS не создаётся.
- Токен Cloudflare берётся из нативной Variable Group задачи №05.
- `cloudflared` устанавливается из подписанного Cloudflare APT репозитория;
  токен туннеля хранится `root:root 0600` и не выводится в Ansible/Semaphore.
- Повторный Apply не пересоздаёт туннель, не трогает DEV-токен и не меняет
  PVE, DNS других сервисов, Access policy или старый общий Tunnel.
- Аудит Cloudflare в №08 явный, bootstrap без секретов вызывает `skip`.
- Готовность: `/` origin HTTPS/CA OK, туннель healthy, конфигурация и
  DNS readback, публичный HTTPS 302 на Cloudflare Access, повторное
  выполнение идемпотентно.
