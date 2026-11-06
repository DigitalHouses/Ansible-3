# №08 — Semaphore и Cloudflare Access

Веб-доступ к Semaphore на сервере Runner через выделенный Cloudflare Tunnel
`<site-id>-semaphore` и адрес `https://<site-id>-pve-semaphore.digitalhouses.vip/`.
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

## Исправление публичного имени

Согласованный стандарт для Semaphore на Proxmox: `https://<site-id>-pve-semaphore.digitalhouses.vip/`.
При обновлении №08 проверяет старый маршрут `<site-id>-semaphore.digitalhouses.vip`,
если он существует, добавляет новый в **тот же** tunnel, проверяет
Cloudflare Access с корректными SNI/TLS, затем удаляет старый маршрут и
DNS без перенаправления. UUID, имя и token туннеля не меняются. При
повторном применении все проверки выполняются без изменений.

## Network Error: `web_host` после Cloudflare Access

В HTTP-странице Semaphore значение `web_host` попадает в `<base href>`.
Если там `https://<runner-ip>:3000/`, внешний браузер пытается получить JS/API
по локальному IP, поэтому видит `Network Error`. №08 применяет
`web_host=https://<site-id>-pve-semaphore.digitalhouses.vip` только после
проверенной публикации Cloudflare. Остальные параметры `config.json`,
включая cookie keys, остаются неизменными. Для штатного DEV API и других
внутренних задач используется исходный IPv4 `eth0` Runner, независимо от
`web_host`. Поскольку task08 исполняет сам Semaphore, Ansible планирует
однократный рестарт службы после завершения задания (transient systemd).
Повторный запуск проверяет `<base href>` и не меняет конфигурацию.
