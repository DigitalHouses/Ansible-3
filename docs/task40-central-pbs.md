# №40 — Central PBS (`dh-core`)

**Актуальное состояние (12.11.2026):** `dh-core / Media Server + PBS — VM2243, 192.168.11.243` реально работает. Перенесён из VM2250/.250 без пересоздания ОС и без изменения физического ZFS-диска. Сохранены оба datastore `pbs-serzhan`, `pbs-core`; PVE Storage `pbs-serzhan` перенаправлен на `.243`, а PVE Backup Job исключает VM2243. Ниже сохранены исторические записи исходных аудитов до миграции.

**Этап 1 (история): только аудит, без изменения серверов или хранилищ.**
В Semaphore CORE есть самостоятельная задача `40-Central PBS`.
Её нельзя выполнять через `serzhan-home` HOME Semaphore.

## Фактическая база (аудит 12.11.2026)

- `dh-core / ASRock PVE — 192.168.11.240`: отдельный узел, а не Beelink HOME.
- `dh-core / Ansible + Semaphore — CT1241, 192.168.11.241`: CORE профиль, отдельный каталог.
- `dh-core / Legacy Media Server — VM2250, 192.168.11.250`: PBS 4.2.9,
  datastore `pbs-serzhan` на `serzhan-pool/pbs-serzhan` (занято около 315 ГБ).
  Это работающие копии; **не переиспользовать и не переименовывать** без
  отдельного плана миграции.
- `dh-core / Standard Media Server — VM2243, 192.168.11.243`: пока **не создан**.
- `serzhan-home / Local PBS — VM2223, 192.168.11.223`: TCP 8007 доступен
  напрямую через LAN; CORE и HOME владельца не требуют Cloudflare-маршрута.
- В legacy PBS нет Remote и Sync Job. Рабочая PVE Storage `pbs-serzhan`
  обслуживает существующий старый режим резервирования.

## №40, текущая реализация

Проверяет локальные `site-id=dh-core`, `site-profile=core`, стандарт CORE
PVE `.240`, pinned SSH из bootstrap; читает PVE VM и Storage через pvesh;
проверяет только TCP reachability HOME PBS. Выводит статусы в журнал.
Ничего не создаёт, не удаляет, не запускает копирование, не обновляет
credentials, не меняет ZFS, VM, диски, firewall, Cloudflare или HOME.

## Следующий этап №40: Apply после отдельного решения

1. Утвердить место и размер **отдельного центрального datastore**, не
   смешивая его со старым `pbs-serzhan`. Существующий ZFS пул принадлежит
   legacy VM2250; по S24 целевой CORE Media — VM2243. Нельзя передавать
   один и тот же сырой диск двум работающим VM.
2. Подготовить на HOME ограниченный **читающий все требуемые backup groups**
   PBS identity для CORE. `Datastore.Backup` не даёт читать чужие группы;
   разрешения должны позволять полный Pull, но не удаление источника.
3. Создать на CORE Remote на `serzhan-home`, проверить TLS fingerprint,
   предоставить отдельный datastore namespace для этого HOME и штатный
   PBS Pull Sync Job. `remove-vanished=false` и независимая retention
   policy. Сначала ручной пилот, затем расписание и verify/restore.
4. Добавить остальные HOME по их уникальным подсетям через защищённый
   Cloudflare Private Network. Данные по объектам из S24.

Не включать автоматический перенос документов и HA до появления самих
источников архивов на локальном PBS.

## Живая приёмка этапа 1 (12.11.2026)

CORE Semaphore `dh-core / Ansible — CT1241, 192.168.11.241`:

- №00: Job #2 `success`, каталог пополнился `40-Central PBS`.
- №40: Job #3 `success`, `runner ok=4`, `core40_pve ok=7`,
  `changed=0`, `failed=0`.
- Вывод: `CORE40_SERZHAN_HOME_PBS=REACHABLE`,
  `CORE40_STANDARD_MEDIA_VM2243=ABSENT`,
  `CORE40_LEGACY_MEDIA_VM2250=PRESENT`,
  `CORE40_LEGACY_PBS_SERZHAN=PRESENT`,
  `CORE40_CENTRAL_PBS_STORAGE=NOT_CONFIGURED`,
  `CORE40_PULL_SYNC=NOT_CONFIGURED`.

Аудит принят; **конфигурация приёма копий и восстановление не проверены**,
поскольку не создавались Central datastore, Remote или Sync Job.

## Этап 2: отдельный центральный datastore на существующей VM2250

Решение владельца: не пересоздавать и не перенумеровывать legacy
`dh-core / Media Server + PBS — VM2250, 192.168.11.250`.
В №40 добавлено отдельное действие `prepare`, по умолчанию остаётся
`audit`. `prepare` создаёт только **`serzhan-pool/pbs-core`** как новый
ZFS filesystem и регистрирует PBS datastore **`pbs-core`** на пути
`/serzhan-pool/pbs-core`. Работает из `dh-core / Semaphore — CT1241,
192.168.11.241` через pinned SSH к `dh-core / ASRock PVE,
192.168.11.240` и штатный Proxmox Guest Agent существующей VM2250.

До операции проверяются идентичность VM2250, здоровье пула, datastore
`pbs-serzhan` и отсутствие конфликтов имени, ZFS-объекта, mountpoint
или чужих файлов. При повторном запуске совпадающие конфигурации
сохраняются, чужие — блокируются. Никаких стираний, импорта диска,
переноса ZFS, удаления backup, изменения PVE Storage, PBS Remotes,
Sync Jobs, credentials или prune нет.

**Ограничение:** `pbs-core` и `pbs-serzhan` находятся в одном физическом
пуле `serzhan-pool`, поэтому физически не независимы друг от друга.
Они логически разделены; независимость копий обеспечит source HOME
на другой машине и следующий внешний уровень B2. В `pbs-core`
пока нет собственных Prune/GC/Verify jobs и backup snapshots.

Для первого Pull нужны отдельный source API-токен с `DatastoreReader`
на `serzhan-home / Local PBS, 192.168.11.223`, закреплённый TLS
fingerprint и отдельная настройка CORE Remote и Sync Job. Этот этап
ещё не меняет источник.

## Живая приёмка этапа 2 (12.11.2026)

CORE Semaphore `dh-core / Ansible + Semaphore — CT1241, 192.168.11.241`:

- №00: Job #4 `success`, Survey №40 обновлён: `audit`/`prepare`.
- №40 `prepare`: Job #5 `success`, `core40_pve ok=30 changed=3 failed=0`;
  созданы **только** `serzhan-pool/pbs-core` и PBS datastore `pbs-core`
  внутри `dh-core / Legacy Media/PBS — VM2250, 192.168.11.250`.
- Независимая проверка: PBS видит оба datastore на разных путях;
  ZFS `pbs-core` смонтирован, занято около 24 МБ (служебные метаданные),
  старый `pbs-serzhan` содержит около 315 ГБ и сохранил прежние
  Prune/GC; Remote/Sync Jobs не появились. PBS HTTPS доступен.
- `pbs-core` намеренно **не добавлялся в PVE Storage**; он предназначен
  только как серверная цель PBS Pull Sync, а не локальный backup job PVE.
- Повторный `prepare`, CORE Semaphore Job #6: `success`, `core40_pve ok=25 changed=0 failed=0`, `runner ok=4 changed=0 failed=0`.
  Dataset и datastore не пересозданы — идемпотентность подтверждена.

**Ближайшая зависимость:** на `serzhan-home / Local PBS — VM2223,
192.168.11.223` нужен отдельный токен с `DatastoreReader` и
`DatastoreAudit` для всех нужных backup groups и закреплённый
сертификат. Существующий токен записи `root@pam!pve-local`
**не следует** применять для Pull. После этого №40 сможет создать
CORE Remote, sync в namespace `serzhan-home` без `remove-vanished`,
запустить ручной пилот и отдельно настроить retention/Verify/GC.

## Транспорт для всех HOME (решение владельца, 12.11.2026)

**Этот репозиторий/чат развивает только CORE №40.** Любые задачи HOME,
включая подготовку локального PBS, Cloudflare Tunnel и выдачу credential,
реализуются в соответствующих HOME-чатах. CORE здесь только потребитель
готового HOME-подключения. Никаких HOME-файлов или HOME-заданий из этого
чата не создаём.

Каждый HOME, включая `serzhan-home`, считается удалённым для синхронизации:

- На HOME существующий `cloudflared` устанавливает исходящее соединение
  к Cloudflare. HOME-часть обсуждается и реализуется отдельно.
- На `dh-core / Media/PBS — VM2243, 192.168.11.243`
  клиент Cloudflare One должен направлять трафик к адресу PBS HOME
  через private network route (для PBS достаточно адреса /32).
  CORE №40 отвечает только за клиент, проверку маршрута и Pull Sync.
- `serzhan-home / PBS — VM2223, 192.168.11.223` — первый пилот.
  Из-за общей физической LAN `192.168.11.0/24` маршрут /32 должен
  приоритетно идти через Cloudflare, а не через `eth0`. Это проверяем
  именно из CORE PBS VM, не по IP-ответу из CORE Runner.
- Подключение к PBS использует нативный протокол HTTPS на TCP 8007
  и штатную PBS-аутентификацию. Без дополнительных SSH proxy/forced
  commands, ручного ввода токенов, Access service token headers или
  отдельного публичного прокси для PBS.
- PBS Remote и Pull Sync создаём только после подтверждённого маршрута
  и получения из HOME корректного параметра авторизации по согласованному
  стандартному контракту (его готовит отдельный HOME-чат). Никаких
  `remove-vanished`, автоматических удалений или нового пользовательского
  самописного кода.

В текущей реализации CORE №40 оставлены работающие режимы `audit`
(по умолчанию) и `prepare` (создать отдельный datastore). Прежний,
не запущенный режим `configure` с ручным вводом PBS-токена удалён
из каталога, пока не согласован штатный источник credentials. Старые
данные `pbs-serzhan` и новый `pbs-core` сохраняются без изменений.

Проверка CORE транспорта начнётся с `ip route get 192.168.11.223`
**внутри VM2243**. Отчёт `DIRECT_LAN_NOT_ACCEPTED` — ожидаемое
состояние до подготовки Cloudflare. Он не означает отказ PBS.

## Приёмка исправления границ проекта (12.11.2026)

- CORE №00 Job #8 `success`; Survey №40 оставляет только `audit` и `prepare`.
- CORE №40 Job #9 `success`: `runner ok=2 changed=0 failed=0`,
  `core40_pve ok=10 changed=0 failed=0`.
- `CORE40_SOURCE_ROUTE=DIRECT_LAN_NOT_ACCEPTED` подтверждён из реальной
  CORE PBS VM2250. Ранее проверенная локальная TCP-доступность HOME
  **не считается проверкой Cloudflare**.
- За пределами CORE не было изменений: HOME-задачи и credential-токены
  не создавались, PBS Remote/Sync Jobs не активированы.

## Живая приёмка перенумерации CORE Media/PBS (12.11.2026)

- На `dh-core / ASRock PVE — 192.168.11.240` старую VM2250
  корректно выключили. Без `qm destroy` и переустановки.
- Переименованы только два LVM-Thin тома `pve/vm-2250-disk-0` →
  `pve/vm-2243-disk-0` и `pve/vm-2250-cloudinit` →
  `pve/vm-2243-cloudinit`, а также конфигурация VMID.
- `dh-core / Media Server + PBS — VM2243, 192.168.11.243`
  запущена с прежними MAC, PCI passthrough GPU и SATA-контроллера.
  Гостевой Linux hostname и имя Proxmox VM пока **сохранены** как
  `mediaserver-serzhan`; отдельное переименование не требовалось.
- Гостевая сеть Netplan и Cloud-Init используют `.243`. Портал,
  rclone GUI и PBS отвечают HTTP 200. ZFS `serzhan-pool` ONLINE.
- PVE Storage `pbs-serzhan` active; прежний токен и сертификат PBS
  не менялись. PVE Backup Job `dh-local-pbs-serzhan` исключает VM2243.
- Существующие datastore `pbs-serzhan` и `pbs-core` доступны по
  исходным путям. PBS Remote/Sync Jobs пока не настроены.
- Резервные копии исходных файлов PVE: `/var/lib/digitalhouses/
  core-media-2243-migration-20261112/`. Копии изменённых файлов
  гостя: `/root/dh-core-2243-migration/`.
- Существующий локальный сертификат `media-account-pki/server.crt`
  проверен: SAN по-прежнему содержит **192.168.11.250**. Он не
  перевыпускался в рамках смены VMID/IP; при обращении к сервису,
  использующему этот сертификат, по IP `.243` TLS-проверка имени
  может не пройти. Это отдельно от штатного PBS TLS (PBS/PVE работает).

## Приёмка CORE №40 после переноса VM2243 (12.11.2026)

- CORE Semaphore Job #10 (`audit`): `success`, `core40_pve ok=10 changed=0 failed=0`, `runner ok=2 changed=0 failed=0`. Показано `CORE40_STANDARD_MEDIA_VM2243=PRESENT`, `CORE40_LEGACY_MEDIA_VM2250=ABSENT` и правильный `CORE40_TARGET_GUEST=dh-core/VM2243/192.168.11.243`.
- CORE Semaphore Job #11 (`prepare`): `success`, `core40_pve ok=28 changed=0 failed=0`, `runner ok=2 changed=0 failed=0`; оба datastore и mountpoint ZFS приняты без повторного создания.
- Cloudflare на CORE/HOME **не меняли**. Следующий этап туннелей выполняется в профильном чате, по отдельному решению пользователя.
