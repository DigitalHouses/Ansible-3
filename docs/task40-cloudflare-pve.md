# №40 — Cloudflare Tunnel → PVE

Канонический адрес `dh-<site_id>-pve.digitalhouses.vip`.

**Назначение:** безопасно исправить origin существующего dedicated Tunnel
`<site_id>-pve` после изменения IP адреса PVE. IP определяется по
`/etc/digitalhouses/pve.yml` Runner, не вводится вручную в Survey.

- `audit` (по умолчанию): проверяет CA-валидный PVE API через
  `curl --cacert` (Proxmox CA legacy Key Usage несовместим с Python SSL), защиту
  Cloudflare Access (анонимный 302 на login), zone/account, один healthy
  dedicated tunnel, DNS CNAME и строгий TLS; показывает старый и новый origin.
- `apply`: меняет **только** `config.ingress[0].service` через официальный
  Cloudflare API (native `ansible.builtin.uri`), сохраняет остальной конфиг
  без изменений; подтверждает GET readback и Access после обновления.
- Existing native Semaphore task №05 хранит `DH_CLOUDFLARE_API_TOKEN`.
  Новый токен/инструмент/отдельный клиент не требуются.
- Shared site Tunnel, DNS records, Access apps/policies, Connector token,
  systemd cloudflared, PVE network и VM/LXC не изменяются. Если обнаружен
  чужой ingress, ownership/TLS drift или отсутствует Access — fail closed.
- Не создаёт Tunnel с нуля: первоначальное provisioning потребует
  отдельной согласованной задачи.

**Acceptance:** `audit` перед `apply`; проверка `ORIGIN_DESIRED` по
фактическому IP; Cloudflare API readback с `noTLSVerify=false` и
`caPool=/etc/cloudflared/dh-pve-ca.pem`; Access 302; повторный `apply`
`changed=0`. Доступ авторизованного пользователя после Access проверяется
в браузере отдельно.
