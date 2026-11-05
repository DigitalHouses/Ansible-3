# №80 — Медиасервер (Ansible-3)

**Статус:** в разработке. Подготовлены read-only аудит, инфраструктурные apply-блоки и черновой native app-onboarding. Всё применение преднамеренно заблокировано до PVE. Задача не зарегистрирована в каталоге Semaphore.

## Цель и границы

Одна задача Semaphore: VM → SATA/ZFS → приложения → встроенная приёмка №81. Никакого собственного Python, shell-оркестраторов, дополнительных workers или повторных approvals.

Параметры: PVE endpoint — только из Runner /etc/digitalhouses/pve.yml; идентификатор сайта — /etc/digitalhouses/site-id; конфигурация — приватный DigitalHouses/site-<site-id>, inventories/<site-id>/site.yml и media_vm.yml, credential №05.

**Состояние декларации 05.11.2026:** VMID 2232, mediaserver-serzhan, 192.168.11.232/24, Intel Arc A310 0000:2f:00.0, SATA 0000:2b:00.0, ZFS serzhan-pool, Hitachi 4 ТБ. Это не верифицированное живое состояние. Не переносить старые параметры Beelink/VM 2238/Samsung и их проверки NTFS/WWN.

В site manifest остаётся backup_export.pve_host=192.168.11.6, а также старые dh- ссылки портала; источник PVE endpoint — Runner, не эти устаревающие поля. Перенос backup/NFS вне №80.

## Два обязательных выбора Semaphore, без default

- VM: keep — существующая проверенная VM; create — только отсутствующая; recreate — удалить только собственную VM и её виртуальные диски, затем единый create.
- Disk: import — импорт существующего ZFS без стирания; erase — стереть только диск за выделенным SATA-контроллером и создать ZFS.

Шесть комбинаций — не шесть реализаций. Выбор в Semaphore достаточен как разрешение на действие. Технические проверки обязательны: exact VM, PCI controller, отсутствие чужого VM owner, ровно один физический диск за SATA в госте, исключён системный диск и чужой/multi-vdev ZFS. Import не может переходить в erase по ошибке. Импортируемые пулы не переименовываются.

## Этапы реализации

1. Каноническая site identity, доверенный PVE SSH ключ после №10, точная VM/PCI конфигурация.
2. Штатный Ansible и qm: keep/create/recreate, Debian 13, 2 vCPU, RAM 4096, boot 64 GiB, balloon off, GPU/SATA passthrough из private site manifest.
3. QGA для доверенного SSH ключа guest, только один SATA-диск, native zpool/zfs, declared datasets, директории, автомонтирование. Никаких дополнительных технических approvals.
4. Plex, Jellyfin, qBittorrent, Radarr, Sonarr, Prowlarr, Filestash, Sambee, digitalhouses_plex_agent, локальный портал и авторизация native API/CLI. При необходимости собственного Python сначала отдельное техническое согласование; не копировать старые custom Python tools.
5. SMB shares Media, Documents, Backups, DigitalHouses; Bonjour, Plex autoscan, медиапути, CPU/ARC и GPU. Общий пользовательский пароль 6–8 символов, первичный — 8, без логирования; Plex со своей учёткой. Нельзя открывать смену пароля через незащищённый HTTP.
6. №81 как приёмка внутри №80: VM, QGA, ZFS, GPU, SMB, приложения/логины/порты, библиотека, повторное исполнение.

## Исключения

PBS, PVE backup jobs, legacy NFS cleanup, изменение PVE IP, публикация SMB в Internet, сторонние VM и Cloudflare PVE/Quantum/Semaphore. Media Cloudflare — последующий отдельный этап; новый tunnel или Access не создавать неявно.

## Реализовано в ветке

- Режим audit: читает оба приватных manifest через токен №05, сверяет site/name/VMID/PCI, подключается к PVE по закреплённому SSH №10, читает VM configuration/status, наличие GPU/SATA и чужую привязку SATA. Возвращает MEDIA80_AUDIT_ONLY.
- Подготовленный apply-контур (пока недостижим): нативный qm lifecycle для keep/create/recreate, первичный cloud-init/QGA, сверка ED25519 через QGA и SSH, SATA vendor/device/class, native ZFS import/erase, datasets, native ZFS boot, QGA/GPU/ARC/swap. Отказ при чужой VM, controller или неверном ZFS. В отличие от старой версии, qm destroy не включает purge backup jobs.
- Гостевая часть (пока недостижима): два POSIX/Samba пользователя из site-repo, пароль на ZFS (генерируется только при отсутствии, сохраняется при повторах), четыре закрытых SMB share, Bonjour, базовая локальная страница на 80 без ложной функции смены пароля.
- Native Plex: официальный signed APT источник, системный сервис, Intel render/media group, проверка HTTP identity и доступа к media dataset. Создание только отсутствующих библиотек Фильмы/Сериалы/Музыка штатным `Plex Media Scanner`, определение ID/типа из Plex SQLite только через `sqlite3 -readonly`, проверка результата на диске; существующие библиотеки не перезаписываются. Четыре штатных атрибута Preferences.xml (auto + partial + periodic 900s) через `community.general.xml` с остановкой Plex только при изменении. Не создаём отдельный сканирующий сервис и не трогаем Plex account claim.
- Native Radarr, Sonarr, Prowlarr: checksum-pinned архивы из прежнего media-контракта, сервисы и официальные host-config API. Для fresh install — сначала только loopback, затем Forms+owner credentials и проверка authenticationRequired перед включением LAN. Настроенный чужой пользователь не перезаписывается. **Реальную авторизацию пользователя и совместимость pinned API обязательно проверить live.**
- Native qBittorrent: Debian package, ZFS paths, loopback-only firstboot, password владельца через штатный WebAPI, контроль выключенного LAN bypass, проверка анонимного отказа и входа владельца по LAN. Существующий пароль не сбрасывать при повторном запуске.
- Native Jellyfin: официальный Debian repository, первый запуск с временным systemd loopback policy, штатные Startup/User/Complete API, проверка входа с общим паролем, три библиотеки Movies/TV Shows/Music, запрет перенастройки чужого администратора. Дополнительно — QSV/HEVC только для известного заводского профиля: GPU render node, реальный VA-API Intel под пользователем Jellyfin, отказ при активном ffmpeg, остановка службы только при изменении, сохранение остальных кодеков. `tests/media-jellyfin-qsv.yml` проверяет корректную замену XML и повторный запуск: `ok=10, failed=0`. Проверку фактического транскодирования на GPU ещё нужно выполнить live.
- Native Filestash: штатный бинарный сервис, bcrypt admin-hash от единого пароля только при первой настройке, SMB passthrough к `127.0.0.1` с Go-шаблонами username/password, предварительно сохранённый 16-символьный secret_key, реальная проверка расшифрованного middleware через admin API и наличия SMB login form. Конфигурация существующего сервиса не перезаписывается; чужой backend и неправильный пароль блокируют выполнение.
- Native Sambee: официальный Compose v2 + persistent `/opt/dh-sambee/data`, конфигурация имени владельца без пароля, firstboot `127.0.0.1:8000`, временный пароль берётся только из защищённых Docker logs и меняется официальным API, после подтверждения общего пароля открывается LAN. Для уже опубликованного экземпляра до `compose up` требуется успешная авторизация владельца; SQLite никогда не редактируется.
- Native Arr wiring: через `ansible.builtin.uri` получаем действующие API keys из локального config.xml, проверяем ZFS root и категории qBittorrent, добавляем отсутствующие rootfolder и QBittorrent download-client providers в Radarr/Sonarr/Prowlarr, а также отсутствующие ссылки Prowlarr→Radarr/Sonarr. Для каждого нового provider используются штатные `/schema`, `/test`, `/POST` и повторный GET. Существующие подключения с теми же именами не перезаписываются. Indexers/торренты не добавляются автоматически.
- Existing DigitalHouses Plex Agent v0.8.5: продукт устанавливается штатным tagged installer с проверенным SHA256, секреты MQTT передаются Ansible template с `no_log`, системный GPU helper и PMU status проверяются через `slurp`/`from_json`, без новых Python snippets. Plex local admin token обязан существовать; учётную запись Plex не пытаемся захватывать автоматически.
- Встроенная №81 оформлена в `tasks/media-accept-pve.yml`, `tasks/media-accept-guest.yml`, `tasks/media-accept-smb.yml` и вызывается в общем playbook после соответствующих стадий. PVE: VM identity, core/RAM/balloon, GPU/SATA PCI, running/QGA. Guest: healthy ZFS, declared datasets и ZFS mount, systemd, TCP endpoints, LAN portal, неавторизованный Arr/qBittorrent API, Jellyfin/Plex libraries, Plex account claim marker + scan settings, реальные входы qBittorrent/Sambee/Filestash, все 4 SMB-шары под owner/admin. Для SMB используются только временные файлы `0600` в `/run`, удаляемые в `always` и скрытые через `no_log`. **Это подготовленные тесты, а не live-приёмка.**
- `tests/media-native-render.yml` — офлайн-шаблоны, `ok=6, failed=0`. `tests/media-jellyfin-qsv.yml` — заводская QSV/HEVC-перенастройка и идемпотентность, `ok=10, failed=0`. `tests/media-plex-xml.yml` сначала не работал на DEV без `lxml`, затем успешно запущен (`ok=6, failed=0`) в изолированном временном окружении с распакованными Debian `python3-lxml` и `libxslt1.1`. Системные пакеты DEV не менялись. Guest получает `python3-lxml` через нативный Ansible apt. Ни один офлайн-тест не заменяет live E2E.
- Нового собственного Python или Bash-оркестратора нет. Вся orchestration-логика — Ansible; системные qm/zpool/zfs/openssl/smbpasswd вызываются нативными задачами.
- Apply жёстко остановлен **до PVE**, не подтверждён ни одним live E2E. Каталог Semaphore не меняется. Это stage implementation, не готовая установка.

**Не готово:** реальная привязка Plex к аккаунту владельца (маркер PlexOnlineToken — не онлайн-проверка), проверка Jellyfin QSV реальным коротким транскодированием, Arr Forms через фактическую форму входа, native password rotation и **живое прохождение встроенной №81**. Plex библиотеки, сканирование, API-интеграция Arr/qBittorrent и Plex Agent подготовлены **только в коде, не проверены E2E**. Filestash/Sambee API требуют живой проверки; Filestash latest-бинарь и Sambee stable-тег ещё не закреплены immutable digest. Первый блокирующий gate стоит **до PVE**, второй `MEDIA80_APPLY_ACCEPTANCE_PENDING` — **после №81** в guest play, чтобы даже при ошибочном снятии первого запрета не объявить задачу завершённой. Live keep/import и destructive E2E ещё не проведены; ни один полный запуск №80 пока не подтверждён.

## Критерии для релиза

- Syntax-check, ansible-lint, git diff --check.
- Live read-only проверка текущих VM, PCI, SATA/ZFS и приложений.
- Шесть комбинаций VM×Disk, безопасный отказ на неверном объекте, отсутствие стирания в import; повторный keep+import.
- Полная E2E-проверка native служб, учетных записей, библиотек, SMB и GPU.
- Разрушительный E2E только по отдельному явному разрешению владельца на точную VM и диск.
- После готовности: зарегистрировать один шаблон №80, выполнить №00, проверить запуск и PLAY RECAP.
