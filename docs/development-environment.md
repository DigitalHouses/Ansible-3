# Ansible-3 — зафиксированное окружение разработки

**Снимок:** 2026-11-03 (Asia/Almaty)  
**Статус:** проверенное действующее окружение, **не** автоматический bootstrap с нуля  
**Основной репозиторий:** [DigitalHouses/Ansible-3](https://github.com/DigitalHouses/Ansible-3), ветка `main`  
**Базовый стандарт:** [ANSIBLE_STANDARDS.md](../ANSIBLE_STANDARDS.md), редакция v0.2  
**Инструкции Codex:** [AGENTS.md](../AGENTS.md)  
**Конфигурация Codex, хранимая в Git:** [.codex/config.toml](../.codex/config.toml)

> Документ фиксирует **фактически проверенное состояние** CT1231, установленные версии, связи сервисов, путь от изменения кода до выполнения и способ восстановления. Файлы токенов, их значения, сеансы аутентификации и приватные настройки объекта в Git **не сохраняются**. Точные ID Semaphore ниже относятся к существующему объекту: после чистого развёртывания они могут отличаться.

## 1. Цель и границы

Цель — поддерживать управляемый цикл **исходники Ansible-3 → разработка Codex → GitHub → Semaphore → запуск Ansible → журнал → диагностика → исправление**, без собственного оркестратора и без необходимости использовать Work.

Действующий `DigitalHouses/dh_ansible` (Ansible-2) и его рабочие шаблоны **не заменены**. Источник и тестовый шаблон Ansible-3 добавлены в тот же проект Semaphore отдельно; изменения нового репозитория не меняют старые шаблоны.

Система состоит из существующих компонентов: Debian LXC, штатного Ansible, Semaphore UI, Codex CLI, готового стороннего MCP-адаптера Semaphore, GitHub и отдельного удалённого доступа Desktop Commander. Codex — **локальный агент в CT**, а не автоматический исполнитель команд из обычного диалога ChatGPT.

## 2. Схема связей

```text
ChatGPT (этот чат) ── GitHub plugin ──> DigitalHouses/Ansible-3 (main)
       │                                      │
       └── Desktop Commander ──> CT1231      │ git fetch/checkout
                                     │        ▼
                                     │   /opt/ansible-3
                                     │        ▲
                                    Codex CLI (интерактивный)
                                     │        │
                                     │  AGENTS.md + .codex/config.toml
                                     │
                                     ▼ MCP stdio
                          /root/.local/bin/semaphore-mcp-local
                                     │ token из root-only файла
                                     ▼
                          johsem/semaphoreui-mcp
                                     │ HTTPS + локальный сертификат
                                     ▼
                    Semaphore UI (порт 3000, проект serzhan-home)
                                     │ repository/inventory/template
                                     ▼
                         Ansible playbook → результат/PLAY RECAP
```

**Важно:** GitHub plugin, Desktop Commander и Codex CLI — разные каналы с разными полномочиями. Доступ на чтение через MCP или запуск из терминального Codex **не означает**, что текущий чат может самостоятельно отправлять административные команды в Semaphore. Ограничения каждого канала действуют отдельно.

## 3. Паспорт CT1231 (фактически измерено)

| Характеристика | Значение на 03.11.2026 | Источник/замечание |
| --- | --- | --- |
| Роль | site runner и окружение разработки Ansible-3 | существующий контейнер |
| Контейнер | Proxmox LXC, CTID **1231** | `pct enter 1231` на PVE |
| Hostname | `ansible-serzhan-home` | `hostname` |
| Операционная система | Debian GNU/Linux **13 (trixie)** | `/etc/os-release` |
| Ядро, видимое из CT | `6.8.12-43-pve` | `uname -r`, ядро хоста PVE |
| Учетная запись для текущей установки | `root` | `id -un` |
| RAM CT | **1,0 GiB** | `free -h` |
| Swap CT | **512 MiB** | `free -h` |
| Корневая файловая система | **16 GiB**, занято около 3 GiB, свободно около 12 GiB | `df -h /`; значения динамические |
| Часовая зона снимка | CT возвращает время с `+00:00` (UTC) | на машине не предполагать Asia/Almaty |
| Semaphore | `digitalhouses-semaphore.service` — `active`, `enabled` | `systemctl show` |
| Listener Semaphore | TCP **3000**, на момент снимка `*:3000` | `ss -lntp`; не равнозначно разрешённому публичному доступу |

Ресурсы CT ограничены: **не добавлять Docker и постоянные фоновые агентские службы без необходимости**. MCP используется через `stdio` и стартует по запросу Codex.

## 4. Проверенные версии и установленные программы

| Продукт | Версия | Команда/расположение |
| --- | --- | --- |
| `ansible-core` | **2.21.4** | `/opt/ansible/venv/bin/ansible-playbook` |
| Semaphore UI | **2.20.16-beta9-5c8c10e0-1793187528** | `/usr/bin/semaphore` |
| Codex CLI | **0.166.0** | `/opt/ansible-3-codex/bin/codex` |
| Node.js | **24.22.0** | `/opt/dh-node/bin/node` |
| npm | **11.19.1** | `/opt/dh-node/bin/npm` |
| Python | **3.13.5** | `/usr/bin/python3` |
| Git | **2.47.3** | `git` |
| uv | **0.13.7** | `/opt/ansible-3-tools/uv-bootstrap/bin/uv` |
| Semaphore MCP | **0.1.0**, сторонний проект `johsem/semaphoreui-mcp` | `/opt/ansible-3-tools/semaphoreui-mcp/.venv/bin/semaphoreui-mcp` |

**Зафиксированная ревизия MCP:** `3093dba0df4679ed253fea3a194ca1a77f8e3b88` (GitHub: [johsem/semaphoreui-mcp](https://github.com/johsem/semaphoreui-mcp)). Исходники установлены отдельно с `uv sync --locked --no-dev`; зависимости привязаны к `uv.lock` из указанной ревизии. Сторонний Python-пакет **не** является самописным Python-кодом проекта Ansible-3.

`ansible-lint` **не обнаружен в PATH** на момент снимка. Отсутствие lint не следует представлять как его успешное прохождение. Codex сообщал предупреждение о `bubblewrap`: для изоляции использовался встроенный fallback; предупреждение само по себе не остановило проверенный read-only запуск.

## 5. Каталоги и их назначение

| Путь | Содержимое / назначение |
| --- | --- |
| `/opt/ansible-3` | рабочая копия **нового** публичного Git-репозитория, ветка `main` |
| `/opt/digitalhouses/src` | рабочая копия **старого** `DigitalHouses/dh_ansible`; не изменять без отдельной задачи |
| `/opt/ansible/venv` | виртуальное окружение штатного Ansible runner |
| `/opt/ansible-3-codex` | изолированная npm-установка Codex CLI |
| `/opt/dh-node` | Node.js/npm для инфраструктурных инструментов |
| `/opt/ansible-3-tools/uv-bootstrap` | окружение с установленным `uv` |
| `/opt/ansible-3-tools/semaphoreui-mcp` | закреплённый сторонний MCP-сервер и его `.venv` |
| `/root/.codex/config.toml` | **локальная глобальная** конфигурация Codex/MCP, вне Git |
| `/opt/ansible-3/.codex/config.toml` | **проектная** конфигурация Codex, в Git |
| `/root/.local/bin/semaphore-mcp-local` | небольшой локальный launcher, читает токен и запускает готовый MCP |
| `/root/.config/ansible-3/semaphore-api-token` | существующий API-токен Semaphore; **секрет, не коммитить** |
| `/etc/semaphore/tls.crt` | архивный локальный сертификат старой схемы HTTPS:3000; для HTTP:80 больше не нужен |
| `/root/.codex/` | локальные сессии и аутентификация Codex; **не копировать в публичный Git** |

Для совместимости с сокращённым `PATH` root-консоли в `/usr/bin/` созданы ссылки: `codex → /opt/ansible-3-codex/bin/codex` и `node → /opt/dh-node/bin/node`. Ссылка `/usr/local/bin/codex` существует также. Это устранило ошибки `command not found` / `env: node: No such file or directory`.

На момент проверки `/opt/ansible-3`, `/opt/ansible-3-codex` и каталог MCP имеют режим `0700`, владелец root; `/root/.codex/config.toml` и файл API-токена — `0600`; launcher — `0700`.

## 6. Разделение конфигурации Codex

**Проектный слой, версионируемый в Git:** [`.codex/config.toml`](../.codex/config.toml).

- `approval_policy = "on-request"` — запрос подтверждений в интерактивной работе.
- `sandbox_mode = "workspace-write"` — разрешённое редактирование рабочего проекта.
- `mcp_servers.semaphore.env.SEMAPHORE_TOOL_PROFILE = "full"` — доступен полный каталог **для отбора**, но не все инструменты доступны агенту.
- `enabled_tools` ограничивает инструменты Semaphore **19** именами: чтение проектов/репозиториев/inventory/environments/templates/tasks, создание **новых** repository/inventory/template, запуск, ожидание, чтение журналов и ошибок.
- `default_tools_approval_mode = "writes"`; явное `approval_mode = "approve"` установлено для `create_repository`, `create_inventory`, `create_template`, `create_task`.

**Глобальный локальный слой:** `/root/.codex/config.toml`, **не** включён в репозиторий:

```toml
[mcp_servers.semaphore]
command = "/root/.local/bin/semaphore-mcp-local"

[mcp_servers.semaphore.env]
SEMAPHORE_URL = "http://127.0.0.1"
SEMAPHORE_CA_BUNDLE = "/etc/semaphore/tls.crt"
SEMAPHORE_PROJECT_IDS = "1"
SEMAPHORE_READ_ONLY = "false"
SEMAPHORE_TOOL_PROFILE = "core"

[mcp_servers.semaphore.tools.create_task]
approval_mode = "approve"

[projects."/opt/ansible-3"]
trust_level = "trusted"
```

Внутри доверенного Ansible-3 проектный профиль переопределяет `core` на `full`, а allowlist скрывает лишние операции. Глобальный `core` остаётся ограниченным вариантом вне этого репозитория.

`codex mcp list` показывает сервер как `enabled`. Пометка `Auth Unsupported` относится к встроенной авторизации MCP-клиента: токен для REST API получает локальный launcher. Корректность подключения подтверждена **реальными вызовами** `get_repository`, `get_template`, `get_task` и `get_task_output`.

**Различие режимов:** интерактивная команда `codex -C /opt/ansible-3` поддерживает запрос разрешения. Неинтерактивный `codex exec` в испытанных запусках имел `approval: never`, поэтому `create_task` отклонялся с сообщением `MCP tool call requires approval`. **Не лечить это отключением подтверждений.**

## 7. Как передаётся API-токен Semaphore

Проверенная локальная реализация launcher `/root/.local/bin/semaphore-mcp-local`:

```sh
#!/bin/sh
set -eu
SEMAPHORE_API_TOKEN=$(cat /root/.config/ansible-3/semaphore-api-token)
export SEMAPHORE_API_TOKEN
exec /opt/ansible-3-tools/semaphoreui-mcp/.venv/bin/semaphoreui-mcp "$@"
```

- Токен хранится только в локальном файле `0600`, значение не помещено в TOML, Git, аргументы команды или примеры документации.
- Launcher `0700` запускается от текущего root-контекста.
- MCP общается с Semaphore по `http://127.0.0.1`.
- `SEMAPHORE_PROJECT_IDS=1` ограничивает доступную область проекта на уровне адаптера; разрешения самого токена/пользователя Semaphore действуют дополнительно.
- `SEMAPHORE_READ_ONLY=false` необходимо для разрешённых действий создания/запуска; фактические изменения всё равно требуют правил approval Codex.
- Секретная часть при восстановлении **вводится/восстанавливается отдельно**, никогда не извлекается из репозитория.

Проверять наличие и режим доступа (`stat`), но **не выводить содержимое** файла токена, `auth.json` или сервисных переменных окружения в диагностику.

## 8. Текущая интеграция Semaphore — подтверждено живым MCP

**Semaphore project:** `serzhan-home`, ID **1**.

| Объект | ID | Привязка / назначение |
| --- | ---: | --- |
| Repository старого Ansible-2 | **1** | `DigitalHouses/dh_ansible` |
| Repository нового Ansible-3 | **4** | `DigitalHouses/Ansible-3`, `https://github.com/DigitalHouses/Ansible-3.git`, ветка `main` |
| Inventory нового smoke | **2** | тип `file`; repository ID 4; файл `inventory/smoke.yml` |
| Template нового smoke | **15** | `Ansible-3 smoke test`; repository ID 4, inventory ID 2, playbook `playbooks/semaphore-smoke.yml` |
| Контрольный запуск | **23** | template ID 15; финальный статус `success` |

**Проверено** через `get_repository`, `get_inventory`, `get_template`, `get_task` и `get_task_output`, после успешного запуска, показанного в терминальном Codex. Новые объекты созданы без изменения старого источника ID 1.

Действующий старый шаблон `10-Создание туннеля CF до PVE`: template ID **5**, playbook `playbooks/request-cloudflare-cutover.yml`, repository **1** (`dh_ansible`). Его успешные запуски **не проверяют** изменения нового Ansible-3.

Не переносить эти числовые ID на другие объекты или в общий код. Для другого дома сначала получать реальные ID через API.

## 9. Подтверждённые тесты (evidence)

| Проверка | Фактический результат | Границы доказательства |
| --- | --- | --- |
| `codex login status` | `Logged in using ChatGPT` | аутентификация локального Codex |
| `codex exec` в read-only | агент прочитал `README.md` и определил стандарт v0.2 | доступ к репозиторию, **не** право административной записи |
| MCP read | проекты, шаблоны, журналы доступны | токен и TLS действуют на чтение |
| Старый template 5, run **22** | интерактивный Codex вызвал `create_task → wait_for_task → get_task_output` после подтверждения; `success` | запуск старой задачи; её код не Ansible-3 |
| Новый template 15, run **23** | `success`; `localhost ok=1 changed=0 unreachable=0 failed=0 skipped=0` | E2E именно репозитория Ansible-3 |
| Локальный синтаксис smoke | `--syntax-check` успешен | проверен только smoke-playbook |
| Локальный smoke | сообщение `Ansible-3 Semaphore smoke test completed.`; `localhost ok=1 changed=0 failed=0` | не проверяет PVE, Cloudflare и другие узлы |

Запуск 23 подтвердил: новое содержимое `main` → repository 4 → inventory 2 → template 15 → runner → статус/журнал. **Полный цикл разработки с автоматическим исправлением ошибок ещё не проверялся**: доказано только создание объектов, разрешённый запуск, ожидание, чтение логов и разбор результата.

## 10. Повседневная работа

**Войти в контейнер (на Proxmox host):**

```bash
pct enter 1231
```

**Начать интерактивную разработку и выполнение с подтверждениями:**

```bash
codex -C /opt/ansible-3
```

Текст задания Codex: что именно изменить, какие ресурсы разрешено затрагивать, какая задача Semaphore является приёмочной. Агент должен читать `AGENTS.md` и `ANSIBLE_STANDARDS.md`, сверять template → repository → playbook → inventory **до** теста.

**Локальная проверка smoke без Semaphore (ничего не меняет в инфраструктуре):**

```bash
cd /opt/ansible-3
/opt/ansible/venv/bin/ansible-playbook \
  -i inventory/smoke.yml \
  playbooks/semaphore-smoke.yml --syntax-check
/opt/ansible/venv/bin/ansible-playbook \
  -i inventory/smoke.yml \
  playbooks/semaphore-smoke.yml
```

**Быстрая диагностика без секретов:**

```bash
codex --version
codex login status
codex mcp list
systemctl is-active digitalhouses-semaphore.service
git -C /opt/ansible-3 status --short
git -C /opt/ansible-3 remote -v
```

Для проверки результата в Semaphore использовать **read**-инструменты MCP. Для запуска/создания объектов — только явное согласованное действие с подтверждением. После каждой работы: указать исходный commit, ID шаблона, ID запуска, итог и `PLAY RECAP`. Пустой `git diff` не означает, что GitHub/Semaphore успешно проверены; эти состояния нужно различать.

## 11. Восстановление окружения после чистого CT1231

Ниже **runbook**, а не проверенный one-command bootstrap. Его нельзя считать автоматически идемпотентным установочным playbook. Сохранять разницу между **пакетной установкой**, **локальными секретами** и **созданием объектов Semaphore**.

### 11.1. Базовая система

1. Восстановить Debian 13 LXC с согласованными ресурсами, hostname и сетевым доступом.
2. Установить стандартные компоненты: Git, Python 3.13 с `venv`/`pip`, сертификаты CA, curl, Node.js **24.22.0** и npm. Источник Node использовать доверенный; не копировать бинарник из Git.
3. Восстановить штатный Ansible runner с `ansible-core==2.21.4` (согласно требованиям установочного проекта) в `/opt/ansible/venv`.
4. Восстановить Semaphore UI **2.20.16-beta9** с его штатным сервисом HTTP:80, конфигурацией, базой и project credentials. **Сохранение содержимого Semaphore и порядок восстановительных операций — отдельная задача**, этот документ не является бэкапом его базы.
5. Восстановить авторизованное подключение Desktop Commander отдельно, если оно требуется для удалённой диагностики ChatGPT. Его учётные данные/идентификаторы не публикуются.

### 11.2. Исходники, Codex и MCP (зафиксированные команды)

```bash
git clone https://github.com/DigitalHouses/Ansible-3.git /opt/ansible-3

# Node/npm должны быть установлены и доступны заранее.
npm install --global --prefix /opt/ansible-3-codex \
  @openai/codex@0.166.0 --no-audit --no-fund

# Нужны python3 с модулем venv, pip и доступ к PyPI/GitHub.
python3 -m venv /opt/ansible-3-tools/uv-bootstrap
/opt/ansible-3-tools/uv-bootstrap/bin/python -m pip install \
  uv==0.13.7

git clone https://github.com/johsem/semaphoreui-mcp.git \
  /opt/ansible-3-tools/semaphoreui-mcp
git -C /opt/ansible-3-tools/semaphoreui-mcp checkout --detach \
  3093dba0df4679ed253fea3a194ca1a77f8e3b88

cd /opt/ansible-3-tools/semaphoreui-mcp
/opt/ansible-3-tools/uv-bootstrap/bin/uv sync --locked --no-dev
```

Если `node` и `codex` не находятся в root-`PATH` (на старом контейнере он был укорочен), проверить `command -v` и настроить ссылки в `/usr/bin` на указанные в разделе 5 исполняемые файлы. **Не перезаписывать существующие системные бинарники без проверки.**

### 11.3. Восстановление локального доступа

1. Восстановить/задать действующий Semaphore API-токен с нужными полномочиями. Создать root-only файл `/root/.config/ansible-3/semaphore-api-token` (режим `0600`), **не вставляя токен в Git или чат**.
2. Создать launcher **ровно по разделу 7** с правами `0700`.
3. Создать глобальный локальный `/root/.codex/config.toml` по **разделу 6** с правами `0600`. Проектные инструкции и настройки уже приедут из Git.
4. Авторизовать Codex: `codex login --device-auth` (при необходимости включить вход по коду устройства в Security Settings ChatGPT); проверить `codex login status`. Не публиковать коды входа и содержимое аутентификационных файлов.
5. Проверить локальный API `http://127.0.0.1/api`, `codex mcp list` и **read-only** вызов к конкретному Semaphore проекту. Публичный HTTPS и Access проверяются отдельно через Cloudflare. Не лечить ошибку прав отключением approvals или песочницы.

### 11.4. Объекты Semaphore

Если восстанавливается старая база Semaphore — сначала убедиться, что repository/inventory/template **уже существуют**; не создавать дубликаты. Если проект создан заново — отдельно создать источник `DigitalHouses/Ansible-3`, smoke inventory и шаблон с привязками из раздела 8. ID после восстановления будут новыми.

Только после проверки привязок и разрешения запуска выполнить один smoke test. Если `success`, `localhost ok=1 changed=0 failed=0` и ожидаемое сообщение присутствуют — окружение разработки прошло базовую приёмку.

## 12. Безопасность и эксплуатационные границы

- Репозиторий **публичный**. Не коммитить `/root/.codex`, токены, пароли, приватные ключи, содержимое `/etc/semaphore/config.json`, .env с секретами, недоступные общественности конфигурации конкретных объектов или полные журналы с credential-данными.
- **Области изменений не смешивать.** Ansible-3 smoke разрешён только на localhost. Действующий Ansible-2 и продуктивные ресурсы не менять как побочный эффект настройки окружения.
- Непрерывный Codex worker, Docker, custom Python, отдельные очереди и watchdogs **не установлены и не требуются** для проверенного цикла.
- Операции `create_repository`, `create_inventory`, `create_template` и `create_task` требуют штатного подтверждения. Удаление и произвольное редактирование существующих объектов в проектный allowlist не включены.
- Разрешение запустить определённый template не даёт универсального разрешения стирать диски, создавать VM или менять DNS: реальная область playbook должна быть проверена отдельно.
- Административный REST API Semaphore слушает `*:3000` внутри CT. Реальная внешняя достижимость/политика firewall **не была доказана** этим снимком; нельзя считать порт локально защищённым только потому, что MCP использует loopback.
- Авторизация через ChatGPT в Codex CLI не равнозначна полномочиям прямого ChatGPT-чата, и не гарантирует отсутствие запросов подтверждения.

## 13. Диагностика типичных неисправностей

| Симптом | Проверка / правильное действие |
| --- | --- |
| `codex: command not found` | проверить `PATH` и ссылки на `/opt/ansible-3-codex/bin/codex` |
| `env: node: No such file or directory` | проверить ссылку `/usr/bin/node` и фактическую установку Node |
| `Not logged in` | `codex login --device-auth`; подтверждение на странице OpenAI |
| На странице device-auth сообщение об отключении | включить вход по коду устройства в Security Settings и начать новое соединение |
| MCP: требуется `SEMAPHORE_API_TOKEN` | проверить **существование и права** root-only файла; запускать MCP через локальный launcher; не печатать токен |
| MCP server `enabled`, но вызовы API не работают | проверить service status, TLS CA, токен/права; сам статус `enabled` не доказывает доступ к API |
| `create_task`: `approval policy is never` | использовать **интерактивный** `codex -C /opt/ansible-3` и штатное подтверждение; не обходить политику |
| Не видны `create_repository` / `create_inventory` / `create_template` | проверить проектный override `full` + `enabled_tools`; перезапустить сеанс Codex после изменения конфигурации |
| Изменения Ansible-3 не появляются в запуске | проверить commit в GitHub и repository_id шаблона; старый template 5 указывает на `dh_ansible` |
| `ansible-playbook` не найден в PATH | использовать `/opt/ansible/venv/bin/ansible-playbook` |
| `ansible-lint` отсутствует | обозначить проверку как невыполненную; не считать её успешной |
| `git diff --no-index` возвращает 1 | это обычный код «файлы отличаются»; для ошибок использовать отдельную проверку, не считать автоматически провалом Ansible |
| В smoke `success`, но нет ожидаемого сообщения | проверить привязки repository/inventory/playbook и фактический журнал, не принимать тест |
| В Semaphore появились дубли объектов | перед созданием искать по имени и репозиторию; не удалять существующее без отдельного разрешения |

## 14. Правила обновления снимка

При обновлении Ansible-3 необходимо поддерживать **один актуальный технический снимок** в этом файле. После изменения версии Codex, Node, Ansible, Semaphore или MCP обновлять таблицу версий, pinned commit/lockfile, команды восстановления, конфигурацию и результаты минимального smoke.

После изменения привязок Semaphore обновлять таблицу IDs и объяснять, что эти ID **не переносимы**. Для каждой новой функции фиксировать: в каком репозитории находится код, какой шаблон запускается, каков результат проверки. Исторические подробности и ранние попытки хранить в [autonomous-development.md](autonomous-development.md).

## 15. Что проверено и что ещё предстоит

**Проверено на 03.11.2026:** установленные версии и пути; работа Codex с аккаунтом ChatGPT; чтение MCP; требуемые approvals в интерактивном Codex; создание отдельного источника/inventory/template Ansible-3; реальный запуск №23 с успешным `PLAY RECAP`; локальный smoke; отсутствие изменений старого Ansible-2 в этой операции.

**Не проверено / не заявлять готовым:** автоматический запуск из **этого** диалога ChatGPT; полностью самостоятельный repair-and-rerun без подтверждения; восстановление CT1231 с нуля одной командой; восстановление базы Semaphore из бэкапа; полный `ansible-lint`; CI/CD; комплексное тестирование будущих инфраструктурных задач Ansible-3.

**Следующий содержательный этап:** разработка согласованных playbooks Ansible-3 по стандарту, начиная с конкретно выбранной задачи и её границ, с проверкой каждого нового шаблона на его собственном исходном репозитории.
