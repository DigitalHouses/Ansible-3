# Ansible-3 — PVE CLI bootstrap

Работает по прежней схеме: **root@pve → одна команда → Site ID → y/n → новый LXC**.

Bootstrap выполняет только:
1. Fresh Debian 13 LXC: CT1231 по умолчанию, hostname `ansible-<site>`,
   IP `<PVE-vmbr0-/24-network>.231`, `onboot=1`, `startup order=2`.
2. Установку штатного `ansible-core==2.21.4` в LXC и clone
   `DigitalHouses/Ansible-3` в `/opt/ansible-3`.
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

## Native Semaphore API access from DEV

Fresh bootstrap also creates the independent **nonadmin** Semaphore user
`dev-automation`, linked only to the site project with role `owner`. This role
can administer that project; it is not a template allowlist. No task is run.
The shared `tasks/dev-access.yml` uses the version-pinned upstream
[API specification](https://github.com/semaphoreui/semaphore/blob/v2.20.16-beta9/api-docs.yml):
`POST /api/users`, login as the dedicated user with `POST /api/auth/login`,
link via `POST /api/project/{id}/users`, then `POST /api/user/tokens`.
Reruns reuse the locally managed password and API token; they do not create another token. An existing username
without its managed password, failed authentication, extra project membership,
or unexpected privileges stops enrollment for manual review. Nothing is deleted.

Runner secrets are root:root 0600 under `/etc/semaphore/`:
`dev-automation-password`, `dev-automation-token`, `dev-automation.curl`.
All credential tasks use `no_log`. The admin catalog token stays on the runner.
Do not remove the managed password: it establishes ownership on reruns.

For an existing runner, run on the **local PVE as root**, from a reviewed
checkout (replace SITE and RUNNER_IP):

```bash
bash bootstrap/enroll-local-dev.sh SITE RUNNER_IP
```

The helper fetches **only** `bootstrap/enroll-dev.yml` and
`bootstrap/tasks/dev-access.yml` over HTTPS from the published
`DigitalHouses/Ansible-3` revision `DH_DEV_ACCESS_REF` (defaults to `main`),
stages them temporarily inside the existing runner, and executes the native
Ansible playbook. It **does not switch** the runner's pinned
`/opt/ansible-3` checkout. Pin `DH_DEV_ACCESS_REF` to a reviewed commit for
repeatable installation; for branch E2E use its explicitly reviewed test ref.

The helper is deliberately restricted to runner CT1231 and the known local
DEV CT1254 at `192.168.11.254/24`. It checks PVE configuration against guest
hostnames and addresses, the runner's `ansible-SITE` name, and DEV's `dev`
account/home and existing `dev-infra` checkout. It invokes only the local
runner enrollment playbook, using the existing admin `catalog-token` to find
exactly the requested site. It transfers only the protected curl config and
public TLS certificate through `pct pull/push` with a root-only temporary
directory. It does not change the dev-infra checkout or any remote host.
Temporary transfer files are removed on exit. DEV receives site-specific files `<site>.curl` and `<site>.crt`, owned by
`dev`, mode 0600, in `/home/dev/.config/ansible-3/` (directory 0700).
Fresh `install.sh` calls it automatically only after these checks succeed;
missing/unverified DEV is skipped with a note. Sites without DEV still work.
Remote sites require separate secure enrollment and certificate verification;
never copy admin credentials to DEV or use `curl -k` / TLS bypass.

As `dev`, use the native API (set the verified site URL and IDs; do not print
the config or token). `-q` disables implicit `.curlrc` loading:

```bash
SITE=serzhan-home  # replace for a different site
API=https://192.168.11.231:3000/api  # use the verified site runner address
CONFIG=/home/dev/.config/ansible-3/$SITE.curl
curl -q --config "$CONFIG" "$API/projects"
# Set PROJECT_ID to the matching site's ID returned above.
curl -q --config "$CONFIG" "$API/project/$PROJECT_ID/templates"
curl -q --config "$CONFIG" "$API/project/$PROJECT_ID/tasks"
curl -q --config "$CONFIG" "$API/project/$PROJECT_ID/tasks/$TASK_ID"
curl -q --config "$CONFIG" "$API/project/$PROJECT_ID/tasks/$TASK_ID/output"
```

**POST requires explicit approval of the concrete template**, after checking
its site, repository, playbook and inventory; retain any client's required
approval. Native curl access must never bypass a rejected MCP/client approval.
Only after that approval, set `APPROVED_TEMPLATE_ID` to that numeric ID:

```bash
curl -q --config "$CONFIG" --request POST \
  --data "{\"template_id\":$APPROVED_TEMPLATE_ID}" \
  "$API/project/$PROJECT_ID/tasks"
```

Record the returned task ID, read status and output until completion, and
report status and PLAY RECAP. Enrollment itself performs no POST to tasks,
adds no other template, and enables no autorun. Syntax checks do not establish
live API acceptance or idempotence; those require an authorized local test.
