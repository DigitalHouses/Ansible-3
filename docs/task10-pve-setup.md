# №10 — Setup PVE: статус реализации

Редакция feature-ветки, не принятая работающая production-задача.

## Цель и границы

Задача управляет только хостом Proxmox VE, идентифицированным bootstrap.
Нельзя затрагивать VM/LXC, разметку дисков, ZFS-пулы, PBS, бэкапы и Cloudflare.
Site-specific IP не является глобальным значением по умолчанию.

## Реализовано в feature

- Audit (по умолчанию): PVE identity, version и vmbr0; storage не опрашивается ради избегания зависших NFS-проб.
- Apply: на PVE 8 установка системных пакетов, Bonjour/Avahi, обновление APT; No-Subscription и upgrade включаются отдельно.
- NUT: драйвер USB HID или SNMP, версия v1/v2c/v3; 10 согласованных брендов плюс Other, модель, IP, секреты SNMP.
- NUT при настройке должен реально отвечать на локальный upsc. Автоматический shutdown/FSD не включается.
- DigitalHouses PVE Agent: существующий installer из canonical release digitalhouses_pve_agent-v0.5.72. MQTT credentials берутся из №05; собственный Python не добавлен.
- В bootstrap: создание Semaphore SSH identity и копирование только публичного SSH ключа на PVE root с ограничением источника, привязка PVE SSH host key.

## Важная зависимость от bootstrap

Уже существующий CT1231 не получает новое SSH-доверие автоматически.
Без него №10 завершится FAIL до подключения к PVE.
Не уничтожать CT1231 ради этого: нужна отдельная согласованная миграция
доверия или новый destructive E2E с явным разрешением.

№00 создаёт отсутствующие шаблоны и не обновляет существующие Survey.
Для новой №10 это штатное поведение.

## Ещё не реализовано

1. IP PVE: 192.168.11.6 → 192.168.11.230. Нужны план сети, проверка
   свободного адреса, поддержка PVE node identity и сертификата,
   восстановление соединения, надёжный rollback, синхронизация inventory.
   Без этого применение из удалённого Ansible опасно.
2. FileBrowser Quantum с доступом ко всему /. Официальная документация
   предупреждает, что root source или включение /var приводит к проблемам
   индексирования. Нужна проверенная схема для этой функциональности с
   авторизацией и loopback-only listener. Данная feature его не устанавливает.
3. PBS storages и backup jobs — отдельный этап после установки PBS.
4. Политика NUT FSD/отключения PVE — отдельная приёмка с физическим UPS.

## Локальная приёмка

Проверить bash -n bootstrap/install.sh, ansible-playbook --syntax-check,
ansible-lint --offline, yamllint и git diff --check.
Предупреждение о dynamic group managed_pve_hosts в syntax-check допустимо:
группа создаётся add_host в первом play.

Live E2E, повторный идемпотентный запуск и реальный Proxmox не проверялись.
