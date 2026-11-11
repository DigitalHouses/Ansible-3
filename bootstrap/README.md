# Ansible-3 — PVE CLI bootstrap

**Обязательный стандарт IPv4 и VM/CT ID:** [S24, ANSIBLE_STANDARDS.md](../ANSIBLE_STANDARDS.md#s24-адресация-и-id-объектов-home--core--согласовано-11112026).
HOME: PVE `.220`, Runner `.221/CT1221`, HAOS `.222/VM2222`,
Media `.223/VM2223`, PostgreSQL `.224/CT1224`.
CORE: PVE `.240`, Runner `.241/CT1241`, HAOS `.242/VM2242`,
Media `.243/VM2243`, PostgreSQL `.244/CT1244`.
Подсеть /24 берётся из текущего `vmbr0` объекта. `192.168.11.0/24` — только сеть владельца; клиентские подсети могут быть другими. Bootstrap создаёт только Runner.

Один bootstrap для двух профилей: **HOME** (по умолчанию) и **CORE**.
Запускать от `root@pve` одной командой. Bootstrap спрашивает профиль,
для HOME — Site ID (`serzhan-home` и т. п.), для CORE использует `dh-core`
без дополнительного ввода. Перед созданием выводит фактический PVE, имя
и адрес LXC и запрашивает подтверждение.

| Параметр | HOME | CORE |
| --- | --- | --- |
| Целевой PVE IP | `<site-prefix>.220` | `<site-prefix>.240` |
| Ansible/Semaphore IP | `<site-prefix>.221` | `<site-prefix>.241` |
| LXC ID | `1221` | `1241` |
| Hostname | `ansible-<site-id>` | `ansible-dh-core` |
| Semaphore project | `<site-id>` | `dh-core` |
| Task catalog (№00) | `catalog/tasks.yml` | `catalog/core-tasks.yml` |

Значения привязаны к профилю, а не к произвольно выбранному IP PVE.
**Bootstrap откажется запускаться, пока текущий PVE не получил целевой
адрес `.220` (HOME) или `.240` (CORE).** Сначала выполнить отдельную
контролируемую миграцию адресов PVE. Сам bootstrap IP PVE не меняет.

Новый Runner сохраняет профиль в `/etc/digitalhouses/site-profile`; при
отсутствии файла у старых HOME Runner задача №00 применяет HOME catalog.
Каталог CORE сначала содержит только №00; задачи для CORE добавляются
позже, начиная с №40.
Штатная автоматическая регистрация токена DEV во время bootstrap работает
только если CT1254 запущен на том же PVE. Для двух независимых PVE
подключение центрального DEV к новому Runner требует отдельной доработки
№08 (не считать CORE API интегрированным после одного bootstrap).

Bootstrap выполняет только:
1. Fresh Debian 13 LXC: CT1221 (HOME) или CT1241 (CORE),
   IP `192.168.11.221/.241`, `onboot=1`, `startup order=2`.
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

Ввод: профиль (ENTER = HOME; `2` = CORE), для HOME — `Site ID`
(например, `serzhan-home`), затем `y/n`.
Например, на HOME PVE владельца `192.168.11.220/24`
результат — CT1221,
`ansible-serzhan-home`, `192.168.11.221/24`.
На CORE PVE `192.168.11.240/24` — CT1241,
`ansible-dh-core`, `192.168.11.241/24`.

**Важное ограничение:** существующие CT1231 и любые другие гости не
уничтожаются и не изменяются. Если целевой ID занят, bootstrap откажется
работать. Восстановление/resume после
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
