# Ansible-3 — PVE CLI bootstrap

Работает по прежней схеме: **root@pve → одна команда → Site ID → y/n → новый LXC**.

Bootstrap выполняет только:
1. Fresh Debian 13 LXC: CT1231 по умолчанию, hostname `ansible-<site>`,
   IP `<PVE-vmbr0-/24-network>.231`, `onboot=1`, `startup order=2`.
2. Установку штатного `ansible-core==2.21.4` в LXC, clone
   `DigitalHouses/Ansible-3` в `/opt/ansible-3` и установку
   закреплённых нативных коллекций из `bootstrap/collections.yml`
   (`community.general==11.2.1`) в общий каталог
   `/usr/share/ansible/collections`, доступный Semaphore.
3. Установку Semaphore `2.20.16-beta9` через Ansible; HTTPS, SQLite,
   отдельный пользователь сервиса.
4. Передачу IP PVE, имени узла и его публичного CA-сертификата в runner
   (`/etc/digitalhouses/pve.yml`, `/etc/digitalhouses/pve-root-ca.pem`).
   Bootstrap не меняет IP PVE.
5. Создание проекта сайта в Semaphore и только ручного шаблона
   **`00-Обновить список задач`**. Запуск шаблона не производится.

№00 при запуске регистрирует *новые* шаблоны, явно добавленные в
`catalog/tasks.yml`. Он не удаляет и не заменяет существующие шаблоны.

**Нового собственного Python-кода нет.** Bash необходим только до появления
Ansible в свежем госте, далее используется `ansible.builtin.*`.

## Продуктивный запуск после приёмки и слияния в main

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DigitalHouses/Ansible-3/main/bootstrap/install.sh)
```

Ввод: `Site ID` (пример `serzhan-home`), затем `y/n`. На PVE
`192.168.11.6/24` стандартный результат — CT1231,
`ansible-serzhan-home`, `192.168.11.231/24`.

**Важное ограничение:** существующий CT1231 не уничтожается и не изменяется.
Если ID занят, bootstrap откажется работать. Восстановление/resume после
частичного сбоя намеренно отсутствует: это fresh-only установщик.

## Испытание на отдельном тестовом LXC

Для тестирования ветки предоставить **отдельные подтверждённо свободные**
CTID, IP и hostname. Команда-шаблон (заполнить значения самостоятельно,
не запускать с угловыми скобками):

```bash
DH_BOOTSTRAP_CTID=<free-ctid> \
DH_BOOTSTRAP_IP=<free-ip> \
DH_BOOTSTRAP_HOSTNAME=ansible-serzhan-home-test \
DH_BOOTSTRAP_REF=feature/pve-cli-bootstrap \
DH_BOOTSTRAP_PROTECTION=0 \
bash <(curl -fsSL https://raw.githubusercontent.com/DigitalHouses/Ansible-3/feature/pve-cli-bootstrap/bootstrap/install.sh)
```

Тестовый LXC можно удалить **только вручную** после оценки.
По умолчанию `DH_BOOTSTRAP_PROTECTION=1`; для disposable test —
`0`. Установщик не удаляет и не перезаписывает гостей, не трогает
PVE storage, VM, media, HA, PBS, Cloudflare или диски.

Журнал на PVE: `/var/log/digitalhouses/ansible-3/bootstrap-*.log` (0600).
Пароль initial admin (не публиковать):
`pct exec <new-ctid> -- cat /root/dh-semaphore-initial-admin-password`.

**Статус: первый вариант, только статическая проверка синтаксиса.**
Требуется чистый E2E-тест отдельного LXC и проверка:
CT, Semaphore HTTPS, project/source/inventory, строго один №00,
отсутствие autorun, неизменность других гостей.

## Штатный доступ центрального DEV к Semaphore (№08)

**Fresh bootstrap** создаёт пользователя `dev-automation` как non-admin Owner
только проекта сайта, выпускает отдельный API-токен и хранит его на Runner
root:root `0600` в `/etc/semaphore/dev-automation-token`.
Глобальный администраторский и catalog токены в DEV не передаются.

После настройки доверенного SSH Runner → PVE bootstrap запускает **тот же**
`playbooks/configure-dev-semaphore.yml`, который используется шаблоном
`08-Настроить доступ DEV к Semaphore`. Это выполняется автоматически,
если рядом уже работает центральный DEV CT1254. Отсутствующий DEV не блокирует
установку сайта. Никакой шаблон Semaphore во время bootstrap не запускается,
в каталоге остаётся только №00.

**Действующий сайт:** после обновления кода из `main` запустить №00 для
добавления №08, затем №08. Запуск №08 не требует вводить credentials объекта
через №05, если доверенный SSH Runner → PVE уже настроен bootstrap.
Секрет для №08 — локально управляемый выделенный доступ, а не пароль PVE.
Временные файлы на PVE удаляются после передачи; в DEV передаются
только защищённый curl config для `dev-automation` и публичный TLS certificate.

**Идемпотентность:** общий `bootstrap/tasks/dev-access.yml` используется и
fresh bootstrap, и №08. Существующий валидный токен не перевыпускается,
при совпадении digest/mode файлы DEV не копируются повторно.
Если identity неожиданно глобальный admin, у него есть другие проекты либо
потерян управляемый пароль — fail closed, никаких удалений.
№08 не создаёт/не запускает производственные шаблоны.

На центральном DEV (выполнить как `dev`):

```bash
CONFIG=/home/dev/.config/ansible-3/serzhan-home.curl
API=http://192.168.11.231/api
curl -q --config "$CONFIG" "$API/projects"
curl -q --config "$CONFIG" "$API/project/1/templates"
curl -q --config "$CONFIG" "$API/project/1/tasks"
curl -q --config "$CONFIG" "$API/project/1/tasks/16/output"
```

В каталоге DEV `/home/dev/.config/ansible-3` права `0700`,
`<site>.curl` и `<site>.crt` — `0600`. Токен не публиковать в Git,
логах или переписке. Не использовать `curl -k`.

После согласования конкретного smoke-шаблона можно создать запуск
штатным `POST /api/project/{id}/tasks`, затем получить статус и `PLAY RECAP`.
Это **не** часть самой №08. Роль Owner даёт права на проект, а не технический
allowlist запуска. Ограничения согласования ChatGPT/Codex должны сохраняться.

Scope этой реализации — совместно размещённые Runner CT1231 и DEV CT1254
(`192.168.11.254/24`). Для удалённых домов потребуется отдельно согласовать
штатный защищённый транспорт; не расширять задачу №08 неявно.
