# Bootstrap Ansible-3 v1 — реализация и проверка

**Дата:** 04.11.2026 · **Ветка:** `feature/bootstrap-v3-v1` · **Статус:** код написан; syntax/lint PASS; PVE E2E **NOT RUN**.

## Что добавлено

| Файл | Функция |
| --- | --- |
| `bootstrap/install.sh` | Однокомандная установка с теми же двумя вопросами, что в Ansible-2; штатные `pct/pveam`; никакого собственного Python |
| `bootstrap/files/dev-ssh-key.pub` | Только **публичный** существующий SSH-ключ DEV CT1254; приватный ключ не копируется |
| `playbooks/bootstrap-runner.yml` | Debian-пакеты, SSH-ключ DEV, SQLite/TLS, Semaphore 2.19.18, администратор, dev-automation и токены |
| `playbooks/bootstrap-semaphore-api.yml` | Создание проекта, Key Store, публичного GitHub repo, локального inventory, environment, №00 и связи Owner через REST |
| `catalog/tasks.yml` | Единственный реализованный шаблон №00; последующие задачи добавляются по мере готовности |
| `playbooks/update-catalog.yml` | №00 — создание отсутствующих и обновление изменённых шаблонов каталога. Чужие/удалённые из манифеста шаблоны **не удаляет** |

Официальный пакет Semaphore `2.19.18` pinned по SHA-256:
`780a3118585d5baa5ed9614e870fa8496f2839450da627596e7b418969eddc72`.
Штатный Python, необходимый Ansible, **разрешён стандартом**; собственный Python-код **не добавлялся**.

Обычный запуск (после проверки и публикации в main/release) задаёт только `Site ID` и `Confirm`. Defaults: CT1231, IP с последним октетом 231 в /24 сети vmbr0, Debian 13, 1 vCPU, RAM 1 GiB, swap 512 MiB, local-lvm 16 GiB, onboot order=2.

## Что проверено

- `bash -n bootstrap/install.sh` — PASS.
- `ansible-playbook --syntax-check` для bootstrap и №00 — PASS.
- `ansible-lint` для bootstrap и №00 — PASS.
- Пакет Semaphore скачан в **локальный DEV** и подтверждён по SHA256.
- Ранее локально в DEV временный Semaphore 2.19.18 успешно отвечал HTTPS 200, создавал проект, None key и публичный репозиторий через API. Это **не E2E всей новой реализации**.
- Устойчивость через повторный apply, создание/запуск №00, новый API-токен и Owner membership **не проверены**.
- Тест доступа DEV→PVE `ssh ... 'pct list'` завершился `Permission denied (publickey,password)`. DEV не имеет подтверждённого канала PVE для создания тестового контейнера.
- CT1199 Legacy, CT1231 (остановлен), CT1254 DEV и остальная инфраструктура **не изменялись**.

## Безопасный E2E на соседнем CT

1. На PVE определить **свободные** CTID и IP в сети vmbr0; не использовать CT1199/1231/1254, IP .199/.231/.254. Проверить отсутствие занятости IP другим устройством и DHCP-конфликта.
2. Запускать **из root-консоли PVE** (не на DEV) с тестовыми переопределениями. Не подставлять неподтверждённые значения:

```bash
DH_BOOTSTRAP_CTID=<FREE_CTID> \
DH_BOOTSTRAP_IP=<FREE_IPV4> \
DH_BOOTSTRAP_GIT_REF=feature/bootstrap-v3-v1 \
bash <(curl -fsSL https://raw.githubusercontent.com/DigitalHouses/Ansible-3/feature/bootstrap-v3-v1/bootstrap/install.sh)
```

3. Ответить `Site ID (<owner>-<type>): serzhan-home`, затем `y`. Проверить `pct config <FREE_CTID>` и `pct status <FREE_CTID>`.
4. Проверить HTTPS/UI Semaphore; пароль администратора только локально: `pct exec <FREE_CTID> -- cat /root/dh-semaphore-admin-password`.
5. Проверить **наличие №00 и её запуск**, проект/repository/inventory/environment, роль DEV Owner, GET API и журнал с `PLAY RECAP`. Без этих проверок не считать интеграцию принятой.
6. После первого полного успешного E2E повторить только Ansible playbook, сравнить `changed` и отсутствие дубликатов; повторное `bootstrap/install.sh` на занятом CTID должно остановиться **до изменений**.
7. Тестовый CT не удалять автоматически. Любое уничтожение только с отдельного разрешения владельца.

**Важно:** код пока находится только в feature-ветке и не прошёл E2E. Не использовать этот установщик на production CT1231 и не объявлять bootstrap принятым.

## Получение DEV-токена после работающего bootstrap

Публичный ключ DEV разрешает SSH на **новый site runner**, но не расширяет права DEV на PVE. Секрет после установки находится в `/etc/semaphore/dev-automation-token` (root:semaphore, 0640). DEV может получить его только по согласованному SSH-каналу и хранить в локальном защищённом файле. **Никаких токенов в Git, чате, stdout bootstrap или CI.**

При другом доме требуется реальная сетевая достижимость DEV→runner (сам публичный SSH-ключ соединение не создаёт); начальный bootstrap не разворачивает Cloudflare.
