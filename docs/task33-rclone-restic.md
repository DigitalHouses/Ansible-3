# №33 — rclone Web GUI + Restic

На уже установленной и проверенной медиасерверной VM задача №33 применяет только штатный rclone Web GUI и установку restic. Она не выполняет VM lifecycle, ZFS import/erase, настройки backup, Cloudflare или повторное создание пользователей.

- **rclone v1.76.0**: официальный Debian пакет с SHA-256, защищённые GUI и API, автозапуск `dh-rclone-gui.service`, как раньше.
- **Restic 0.19.1**: официальный `restic_0.19.1_linux_amd64.bz2` (GitHub restic/restic), pinned SHA-256 с проверки релиза. Распакованный исполняемый файл проходит вторую проверку SHA-256 до установки в `/usr/local/bin/restic`. Дистрибутивный пакет не изменяется. Установка идемпотентна, через только нативные модули Ansible и штатную команду `bzip2`.
- Restic **не создаёт** конфигурации, repository, снимков, заданий резервного копирования, service/timers, credentials. Никакого чтения или изменения существующих бэкапов.
- Приёмка №33 проверяет команду `/usr/local/bin/restic version` с версией 0.19.1. Для проверки из корня PVE: `qm guest exec 2232 -- /usr/local/bin/restic version`.

В Semaphore существующее имя шаблона остаётся **`33-rclone Web GUI`** (без создания дубликата); его playbook `playbooks/media-rclone-gui.yml` включает новый `tasks/media33-restic-apply.yml`. Повторное выполнение №33 разрешено для существующей VM 2232; ZFS/медиа-пользователи не изменяются.
