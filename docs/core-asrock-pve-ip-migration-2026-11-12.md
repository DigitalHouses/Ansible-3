# dh-core — миграция management IPv4 ASRock PVE (12.11.2026)

Статус: **выполнена и проверена на живом узле**. Это была разовая операция
через центральный `DEV — CT1254, 192.168.11.254`, **не** запуск HOME №10.

| Физический сервер | Роль | Адрес |
| --- | --- | --- |
| Beelink S12 | `serzhan-home / PVE` | `192.168.11.220` — не меняли |
| ASRock X570D4U-2L2T | `dh-core / PVE` | `192.168.11.230` → **`192.168.11.240`** |

- Preflight: отсутствие Corosync и `interfaces.new`, освобождённый адрес
  подтверждён `arping -D` (0 ответов); временный IP alias и pinned SSH
  подтвердили доступность нового адреса через центральный DEV.
- Изменены только management IPv4 у `vmbr0` и соответствующая запись
  `/etc/hosts`. Gateway, bridge ports и гостевые адреса не менялись.
- До операции сохранены `/etc/network/interfaces` и `/etc/hosts`,
  установлен локальный systemd rollback timer. После `ifreload -a`
  соединение SSH на новом IP и HTTPS API с доверенным CA проверены;
  rollback timer штатно остановлен (активных timer units нет).
- `pvecm updatecerts --force` выполнен. При перезапуске `pveproxy`
  завис один старый worker в состоянии shutdown, который пришлось завершить;
  `pveproxy.service` затем `active`, API `401` без токена при TLS verify=0.
- `digitalhouses-filebrowser` и отдельный `dh_quantum` nft firewall были
  привязаны к старому IP. Адрес исправлен в
  `/etc/digitalhouses/filebrowser-quantum.yml` и
  `/etc/digitalhouses/filebrowser-lan.nft`, firewall заменён атомарно,
  служба перезапущена. `http://192.168.11.240:8090/health` → `200`;
  `/api/users` без авторизации → `401`.
- Проверено, что на ASRock продолжают работать `dh-core / HA — VM2242`,
  `mediaserver-serzhan — VM2250`, `ansible-legacy — CT1199`,
  `ansible-serzhan-home — CT1231`, `центральный DEV — CT1254`.
  Это существующие имена и ID, **не** автоматическая миграция в CORE.
  Storage `pbs-serzhan` на ASRock был `active` после смены IP.

**Вне области операции:** hostname ASRock остаётся `pve.home`;
не менялись site manifest, Semaphore, Cloudflare Tunnel/Access,
названия VM/LXC и конфигурация других объектов. Перед запуском новых
CORE-заданий идентичность и подключение должны быть приведены к `dh-core`
через отдельный CORE workflow. HOME task №10 не применять к ASRock.
