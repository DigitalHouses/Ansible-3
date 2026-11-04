# Ansible-3 — PVE CLI bootstrap

Работает по прежней схеме: **root@pve → одна команда → Site ID → y/n → новый LXC**.

Bootstrap выполняет только:
1. Fresh Debian 13 LXC: CT1231 по умолчанию, hostname `ansible-<site>`,
   IP `<PVE-vmbr0-/24-network>.231`, `onboot=1`, `startup order=2`.
2. Установку штатного `ansible-core==2.21.4` в LXC и clone
   `DigitalHouses/Ansible-3` в `/opt/ansible-3`.
3. Установку Semaphore `2.20.16-beta9` через Ansible; HTTPS, SQLite,
   отдельный пользователь сервиса.
4. Создание проекта сайта в Semaphore и только ручного шаблона
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
