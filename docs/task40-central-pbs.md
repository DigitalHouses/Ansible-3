# №40 — Central PBS (`dh-core`)

**Этап 1: только аудит, без изменения серверов или хранилищ.**
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
