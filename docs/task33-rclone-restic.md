# №33 — rclone Web GUI + Restic

На уже установленной и проверенной медиасерверной VM задача №33 устанавливает rclone/Restic/PBS, создаёт datastore, подключает PBS к PVE и управляет локальными заданиями backup/Prune/GC/Verify. Она не выполняет VM lifecycle, ZFS import/erase, Cloudflare или повторное создание медиа-пользователей.

- **rclone v1.76.0**: официальный Debian пакет с SHA-256, защищённые GUI и API, автозапуск `dh-rclone-gui.service`, как раньше.
- **Restic 0.19.1**: официальный `restic_0.19.1_linux_amd64.bz2` (GitHub restic/restic), pinned SHA-256 с проверки релиза. Распакованный исполняемый файл проходит вторую проверку SHA-256 до установки в `/usr/local/bin/restic`. Дистрибутивный пакет не изменяется. Установка идемпотентна, через только нативные модули Ansible и штатную команду `bzip2`.
- Restic **не создаёт** конфигурации, repository, снимков, заданий резервного копирования, service/timers, credentials. Никакого чтения или изменения существующих бэкапов.
- Приёмка №33 проверяет команду `/usr/local/bin/restic version` с версией 0.19.1. Для проверки из корня PVE: `qm guest exec 2232 -- /usr/local/bin/restic version`.

В Semaphore существующее имя шаблона остаётся **`33-rclone Web GUI`** (без создания дубликата); его playbook `playbooks/media-rclone-gui.yml` включает новый `tasks/media33-restic-apply.yml`. Повторное выполнение №33 разрешено для существующей VM 2232; ZFS/медиа-пользователи не изменяются.


## Dataset PBS: задача №33

Создаётся **только один** ZFS filesystem `<owner>-pool/pbs-<owner>`, например `serzhan-pool/pbs-serzhan`. Точка монтирования — `/serzhan-pool/pbs-serzhan` (внутри уже импортированного медиа ZFS-пула). Целевой pool, имя владельца и точка монтирования выводятся из существующего приватного `media_vm.yml`, не задаются отдельными аргументами.

Защиты:
- Перед созданием требуется существующий онлайн-пул, ожидаемая корневая точка монтирования и точное имя dataset; новые диски, пулы и разделы не создаются и не стираются.
- Создание `zfs create -o atime=on` выполняется **только при отсутствии** dataset. Родительские настройки ZFS (включая compression/acl) наследуются, другие datasets не меняются.
- Если ожидаемое имя уже используется чужим ZVOL/объектом или каталог по точке монтирования уже занят, задача отказывает до создания, чтобы не скрыть чужие файлы.
- Существующий dataset сохраняет все данные и свойства, кроме `atime`: если он был `off`, №33 исправляет **только на этом PBS dataset** значение на `on` (это обязательное условие безопасности PBS GC). Проверяются mountpoint, `findmnt` и atime.
- Автоматические `quota/refquota/reservation` и рекурсивная смена владельца/разрешений **не добавлены**. Задания backup/Prune/GC/Verify настраиваются отдельно ниже в этой же задаче №33. PBS datastore регистрируется ниже отдельным идемпотентным шагом; права на пустой корень dataset перед регистрацией назначаются системному пользователю `backup`.

№33 также регистрирует **PBS datastore** `pbs-serzhan` с backing path `/serzhan-pool/pbs-serzhan` (только если отсутствует). Перед регистрацией проверяется, что путь на настоящем ZFS, `atime=on`, datastore name/path не заняты другими хранилищами, а каталог пуст. После регистрации проверяется совпадение backing path. ZFS квоты пока не меняются; ограниченный PBS API-токен для локального PVE и расписания создаются следующими шагами №33. Для текущего мини-ПК с одним media/PBS физическим SATA-диском это общий failure domain, поэтому резервная копия должна иметь дополнительное независимое место хранения. В PBS нет требования к специальному ZFS `recordsize`; отдельно менять уже выбранные для медиапула параметры не нужно.


## Подключение локального PVE к PBS через №33

После регистрации PBS datastore задача №33 **без запуска backup** автоматически добавляет в соответствующий PVE раздел `Datacenter → Storage`:

- PVE Storage ID = `pbs-<owner>`, datastore = `pbs-<owner>`, тип `pbs`, content = `backup`, сервер — адрес существующей media VM из site manifest (например, `192.168.11.232:8007`).
- PBS API token = `root@pam!pve-local` с разрешениями `DatastorePowerUser` + `DatastoreAudit` **только** на `/datastore/pbs-<owner>`. Это НЕ root-доступ в PBS: токен обладает лишь явно назначенными привилегиями, независимыми от полномочий `root@pam`.
- PBS token secret генерируется однократно и хранится защищённым файлом `/etc/digitalhouses/pbs-pve-local.token` в media VM; PVE получает копию в штатный root-private файл `/etc/pve/priv/storage/pbs-<owner>.pw`. При первичном создании PVE Storage секрет вводится через штатный запрос пароля в изолированном pseudo-TTY (не как CLI-аргумент) и не попадает в Semaphore logs.
- Устанавливается TLS SHA256 fingerprint, прочитанный из самой media VM по ранее закреплённому SSH host key; self-signed TLS не отключается. Задача сравнивает текущие идентификаторы PVE VM, PBS datastore и PVE storage и не переписывает чужое хранилище.
- Повторный запуск сохраняет токен и существующую конфигурацию, обновляя только секретный файл (если требуется) и fingerprint после доверенного перевыпуска PBS-сертификата. Выдачу нового токена при пропаже сохранённого секрета блокируем во избежание скрытой ротации.
- После подключения Ansible требует `pvesm status --storage pbs-<owner>` со статусом `active`.

Создание расписаний локальных backup, Prune, GC, Verify и исключение VM с PBS теперь выполняет №33; ZFS квоты, центральный PBS, B2 и реальный тест восстановления остаются в №300. Системная VM с PBS не должна неявно резервировать собственный физический диск или backup datastore.


## PBS 4.2 APT: packaged Enterprise источник

После установки `proxmox-backup-server` пакет по умолчанию включает `/etc/apt/sources.list.d/pbs-enterprise.sources`, который без подписки даёт HTTP 401 и блокирует повторный `apt update`.

№30/№33 через общий `tasks/media30-pbs-apply.yml` теперь **до и после** установки пакета проверяют содержимое именно этого файла и добавляют `Enabled: no`, как рекомендует официальный PBS 4.2. Рабочим остаётся `dh-pbs-no-subscription.sources`. Никакие другие APT источники, PVE-хост и данные не затрагиваются. Проверка предотвращает изменение неожиданных файлов.


## Локальные расписания PBS и PVE (№33)

Требование владельца от 2026-11-09: 30 ежедневных точек вместо прежних 7.

- **PVE** создаёт ровно один идемпотентный Backup Job `dh-local-pbs-<owner>` на `pbs-<owner>`, `mode=snapshot`, `all=1`, `exclude=<media_vm.vmid>`, `remove=0`; ежедневно `02:00` по часовому поясу PVE. Исключение host-VM PBS критично против циклического копирования. Другие VM/LXC остаются в области резервирования. Никаких немедленных `vzdump` при №33.
- **PBS**: отдельный штатный PBS 4.2 Prune Job `dh-daily-<owner>` (`keep-daily=30`, `schedule=04:00` ежедневно) на `pbs-<owner>`; у datastore — еженедельный `gc-schedule=sat 06:00`. Проверяется `atime=on` и отсутствие других keep-* политик; чужие datastore не меняются.
- **PBS Verify**: одно управляемое задание `dh-weekly-<owner>`, `schedule=sun 07:00`, `ignore-verified=true`, `outdated-after=30`, `read-threads=1`, `verify-threads=2`. Уже зарегистрированные чужие задания на этом datastore блокируют установку для предупреждения дублирования.
- **Отдельный API-токен PBS Backup Client**, с предварительной штатной установкой пакета `proxmox-backup-client` из официального PBS APT репозитория (новая VM не получает его автоматически при установке только PBS Server), не совпадающий с `root@pam!pve-local`, называется `root@pam!file-client`. Права только `DatastoreBackup` и `DatastoreAudit` на `/datastore/pbs-<owner>`. Secret: `/etc/digitalhouses/pbs-file-client.token` root:root 0600. Файл `/etc/digitalhouses/pbs-file-client.env` root:root 0600 задаёт `PBS_REPOSITORY`, `PBS_PASSWORD_FILE` и `PBS_FINGERPRINT` без помещения секрета в окружение. №33 проверяет `proxmox-backup-client list` с неинтерактивной авторизацией, но не делает клиентских бэкапов.
- **Часовые пояса:** PVE выполняет расписание в локальной TZ хоста; текущая медиасерверная VM использует UTC. Расписания Prune/GC/Verify выполняются по локальной TZ VM, поэтому часы PBS в UI нельзя приравнивать к часам PVE без учёта смещения. №33 не меняет системную TZ медиа VM.
- Перед изменениями все задания сверяются с текущими конфигурациями; чужие job IDs или конфликтующие политики не удаляются/не перезаписываются. Повторное применение безопасно. Backup Job создаётся только после проверки статуса `pbs-<owner>` = active. Без немедленного запуска резервных копий или восстановления.

### Проверки

`pvesh get /cluster/backup --output-format json`, `pvesm status --storage pbs-<owner>`, `proxmox-backup-manager datastore show pbs-<owner> --output-format json`, `proxmox-backup-manager verify-job list --output-format json`.
