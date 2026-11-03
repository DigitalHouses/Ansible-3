# Первый тест Ansible-3 в Semaphore

## Назначение

Минимальный playbook `playbooks/semaphore-smoke.yml` выполняет один `ansible.builtin.debug` на `localhost` без сбора фактов и повышения привилегий. Inventory: `inventory/smoke.yml`. Тест не изменяет инфраструктуру и проверяет получение кода из нового репозитория и исполнение в runner.

## Проверено локально на CT1231

- `/opt/ansible/venv/bin/ansible-playbook -i inventory/smoke.yml playbooks/semaphore-smoke.yml --syntax-check` — успешно.
- Выполнение той же команды без `--syntax-check` — `localhost ok=1 changed=0 failed=0 unreachable=0`, сообщение `Ansible-3 Semaphore smoke test completed.`.
- `ansible-lint` не проверен: исполняемый файл не обнаружен в стандартном PATH.

## Предполагаемые новые объекты Semaphore

Существующий проект `serzhan-home`, ID 1; **действующий Ansible-2 не изменять**.

| Объект | Имя / параметры |
| --- | --- |
| Repository | `DigitalHouses Ansible-3`; `https://github.com/DigitalHouses/Ansible-3.git`; ветка `main` |
| Inventory | `Ansible-3 smoke (local)`; file, repository Ansible-3, путь `inventory/smoke.yml` |
| Task template | `Ansible-3 smoke test`; Ansible, repository Ansible-3, playbook `playbooks/semaphore-smoke.yml`, inventory smoke |
| Переменные / credentials | Не нужны для проверки localhost; использовать только необходимые обязательные поля интерфейса |

Для создания использовать штатные инструменты Semaphore через MCP с отдельным подтверждением операций записи. Не изменять repository ID 1 (`DigitalHouses/dh_ansible`), существующие inventory, environments, templates или расписания.

## Приёмка в Semaphore

Проверить новый repository и привязки нового шаблона. Получить разрешение на один тестовый запуск. Затем `create_task` → `wait_for_task` → `get_task_output`; ожидается статус `success`, сообщение `Ansible-3 Semaphore smoke test completed.`, `localhost: ok=1 changed=0 failed=0 unreachable=0`.

До выполнения нового шаблона результат в Semaphore **не принят**.
