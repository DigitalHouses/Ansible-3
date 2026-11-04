# №10 — Setup PVE: реализация и приёмка

**Статус:** feature PR; код проверяется локально. Живой E2E на PVE не выполнен.

## Что делает задача

- `DH_PVE_MODE=audit` — только hostname, PVE version, vmbr0. Никаких storage/NFS-проб.
- `apply` на PVE 8: APT postinstall, опциональный no-subscription канал
  и обновление без reboot, Bonjour/Avahi, пакеты NUT, PVE Agent.
- NUT: нет UPS / локальный USB / сетевой SNMP; Auto выбирает
  `usbhid-ups` или `snmp-ups`, есть ручной выбор драйвера и MIB.
  10 производителей + Other. Доступ к UPS подтверждается через `upsc`.
  NUT monitor/FSD и реальное отключение UPS **не включаются автоматически**.
- `dh_pve_agent` устанавливается из проверенного canonical tag
  `digitalhouses_pve_agent-v0.5.72`, MQTT host и credentials из №05.
  Если брокера пока нет, агент ожидает MQTT; установка сервиса отдельно.
- FileBrowser Quantum: стабильный upstream `v2.0.2-stable`,
  бинарник SHA256 `5710dc6f51d77f1db884eace44f6952286c49f2ce40b6a59af37e0dc7c4a8bbd`.
  Доступ ко всей ФС `/`, глобальное `viewable: true` **отключает индексирование**.
  Работает от root **только** на `127.0.0.1:8090`; password auth и
  rate limit активны, публичный WebDAV отключён. Password создаёт
  сам Quantum при первом запуске (в журнале systemd), далее смена в UI.
  Никакого публичного ingress без отдельной задачи Cloudflare Access.
  Upstream предупреждает против `/` как source: полномасштабный live
  тест доступа и воздействия на host обязателен перед приёмкой.
- По отдельному выбору `DH_PVE_NETWORK_ACTION=migrate` и с явно
  указанным `DH_PVE_NEW_IP` задача мигрирует одиночный PVE узел.
  Пример согласованного адреса сайта: `192.168.11.230`. Этот адрес
  **не** захардкожен в публичной Ansible-3 роли.

## Безопасная миграция управления PVE

Сначала проверяются отсутствие corosync cluster, GUI pending
`interfaces.new`, конфигурация `vmbr0`, однозначная строка
адреса и запись hostname в `/etc/hosts`, отсутствие ответа на
ARP-probe для нового IP. Проверяется отдельная временная alias
адреса и доступность порта SSH с Runner, затем alias удаляется.

Перед перезаписью двух файлов сохраняются резервные копии и ставится
one-shot systemd rollback timer на 240 секунд. Изменяются только
management IPv4 в `/etc/network/interfaces` и соответствующая
строка `/etc/hosts`. Сеть применяется штатным `ifreload -a` (НЕ
`ifdown/ifup vmbr0`). После переподключения проверяется SSH с pinned
host key, обновляются PVE certificates и проверяется PVE API с CA
verification. Runner `/etc/digitalhouses/pve.yml` обновляется только
после этого; rollback timer снимается последним.

Если выполнение прерывается до подтверждения, таймер возвращает
старые `interfaces` и `hosts`, выполняет `ifreload -a` и
восстанавливает сертификат. **Наличие таймера не заменяет физическую
консоль или out-of-band доступ при сбоях оборудования.**
Сетевой этап по умолчанию **выключен**, при повторном запуске на
уже выставленном IP изменения сети пропускаются.

Не меняются default gateway, bridge ports, interface names,
гостевые IP, ZFS или сетевые настройки VM/LXC. Сайтовые настройки
в приватном репозитории нужно синхронизировать после живого E2E;
задача обновляет только локальный конфиг Runner.

## Как подключить существующий Runner (CT1231)

Новый bootstrap уже умеет создавать Semaphore SSH-ключ и пинить
PVE host identity. Для существующего Runner есть один
неразрушительный инструмент `bootstrap/enroll-existing-runner-ssh.sh`.
Запускается **локально под root на самом PVE** с правом работать
с CT1231. Не делает `pct destroy`, не перезапускает LXC.
Проверяет hostname и тип CT, создаёт ключ под `semaphore` только
при отсутствии, добавляет только публичный ключ в PVE root
`authorized_keys` с `restrict,from=<runner_ip>`, проверяет
SSH host key и SSH авторизацию. Не копирует host private keys.

Команда после доставки проверенного файла на PVE:
`bash bootstrap/enroll-existing-runner-ssh.sh 1231`.

## Критерии приёмки

1. Коммит в `main`, новый шаблон №10 создан штатным №00 в
   правильном Semaphore проекте и указывает на Ansible-3.
2. №10 audit успешен, изменённых файлов на PVE нет.
3. №10 apply (без IP cutover на первом тесте) прошёл: Avahi,
   Quantum `/health` и unauthenticated `/api/users=401`,
   PVE Agent systemd, NUT `upsc` только если UPS выбран.
4. При отдельном согласованном run с миграцией IP PVE API с
   валидным CA и SSH доступны на новом адресе, Runner записал
   новый endpoint; rollback timer снят.
5. Повторный запуск идемпотентен и не затрагивает VM/LXC, диски
   и backup jobs.

## Выполненные локальные проверки

`bash -n`, `yamllint`, `ansible-playbook --syntax-check`,
`ansible-lint --offline`, `git diff --check`; локальный
fixture smoke Quantum (SHA256, /health=200, /api/users=401);
Ansible fixture test выражений IP/hosts и преобразования
PVE identity. Нет живой проверки PVE, NUT оборудования,
сетевого rollback или пароля Quantum на хосте.

## Позже

PBS storage и 2 штатных PVE backup jobs (local/cloud) только
после PBS развёртывания. Cloudflare Access для PVE/Quantum,
HAOS/Mosquitto deployment, NUT shutdown commissioning —
отдельные задачи, не должны запускаться побочно.
