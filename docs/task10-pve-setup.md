# №10 — Setup PVE: реализация и приёмка

**Статус:** PVE baseline/agent/Quantum E2E принят на PVE 8.4.21 (№26, №27); UPS и смена IP ещё не проверены на оборудовании.

## Что делает задача

- `DH_PVE_MODE=audit` — только hostname, PVE version, vmbr0. Никаких storage/NFS-проб.
- `apply` на PVE 8: APT postinstall, опциональный no-subscription канал
  и обновление без reboot, Bonjour/Avahi, пакеты NUT, PVE Agent.
- Имя нового PVE инженер задаёт **при установке** по стандарту
  `pve-<owner>.home.arpa`. №10 считывает `site.owner_slug` из
  `inventories/<site_id>/site.yml` приватного `DigitalHouses/site-<site_id>`
  через существующий GitHub credential №05. `site.id` обязан совпасть с
  идентификатором Runner. Других полей `owner` или значений по умолчанию нет.
  В `audit` выводятся ожидаемый/фактический FQDN и предупреждение о legacy
  имени; **системное имя действующего узла не меняется**. В `apply` Avahi
  публикует `pve-<owner>.local`; это имя независимо от `hostname -s` PVE.
  Записи `*.home.arpa` в локальном DNS — отдельная настройка DNS-сервера,
  №10 их не создаёт. Недоступный site manifest блокирует №10 до изменений.
- NUT Survey №10: ровно **3 поля** — подключение (нет, USB, SNMP v2c,
  SNMP v3), IP сетевого UPS и драйвер (Auto либо явный выбор).
  Auto = `usbhid-ups` для USB, `snmp-ups` для сети; это не аппаратный
  autodetect всех совместимых драйверов. MIB = `auto`, SNMP v3 = SHA/AES.
  Для нестандартного устройства можно задать `DH_PVE_SNMP_MIB`,
  `DH_PVE_SNMP_AUTH_PROTOCOL`, `DH_PVE_SNMP_PRIV_PROTOCOL` и, при
  необходимости старого SNMP v1, `DH_PVE_SNMP_VERSION=v1` в
  native Variable Group объекта. Дополнительных полей Survey нет.
  Производителя и модель получает NUT с устройства, если оно их публикует.
  **SNMP credentials вводятся только в №05**: v2c community; v3 имя
  пользователя, Auth Password, Privacy Password. Пустой ввод сохраняет
  прежнее значение. Секреты хранятся в native Semaphore Variable Group.
  №10 не извлекает забытые секреты из `ups.conf`: при отсутствии нужных
  credentials он останавливается с предложением заполнить №05.
  Пакеты NUT устанавливаются только для выбранного UPS, успех требует
  `upsc ups@127.0.0.1 ups.status`.
  NUT monitor/FSD и реальное отключение UPS **не включаются автоматически**.
- `dh_pve_agent` устанавливается из проверенного canonical tag
  `digitalhouses_pve_agent-v0.5.75` (installer SHA256 проверяется),
  MQTT host и credentials из №05. Уже установленная версия агента
  сохраняется, если версия не старее 0.5.75: №10 обновляет только более старые версии и не понижает новые. В 0.5.73 добавлено чтение RPM через локальный BMC/IPMI; в 0.5.74 исправлены аварийные показания BMC и имена вентиляторов. В 0.5.75 добавлен универсальный `hwmon/PWM` адаптер: пассивное измерение максимальных RPM при режиме `pwmN_enable=0`; активное PWM-управление по умолчанию заблокировано до независимой проверки соответствия каналов. На ASRock Rack X570D4U-2L2T остаётся RPM-only, без автоматической калибровки.
  Ansible-3 только устанавливает проверенный релиз агента. Изменения исходников `digitalhouses_pve_agent` выполняются исключительно в `DigitalHouses/home-assistant-apps`, не в задачах Ansible.
  Если брокера пока нет, агент ожидает MQTT; установка сервиса отдельно.
- FileBrowser Quantum: стабильный upstream `v2.0.2-stable`,
  бинарник SHA256 `5710dc6f51d77f1db884eace44f6952286c49f2ce40b6a59af37e0dc7c4a8bbd`.
  Доступ ко всей ФС `/`, глобальное `viewable: true` **отключает индексирование**.
  Работает от root на management IPv4 PVE `http://<pve-ip>:8090` (для
  serzhan-home `http://192.168.11.220:8090`); password auth и
  rate limit активны, публичный WebDAV отключён. Password создаёт
  сам Quantum при первом запуске (в журнале systemd), далее смена в UI.
  Публичный ingress и его Access контролируются этим же №10.
  Upstream предупреждает против `/` как source: полномасштабный live
  тест доступа и воздействия на host обязателен перед приёмкой.
- По отдельному выбору `DH_PVE_NETWORK_ACTION=migrate` и с явно
  указанным `DH_PVE_NEW_IP` задача мигрирует одиночный PVE узел.
  Пример согласованного адреса сайта: `192.168.11.220`. Этот адрес
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

## Подключение существующего site Runner

**Никакой ручной команды на PVE и пересоздания CT1231.**

Для нового Runner bootstrap уже закрепляет доверенный SSH host key
из самого PVE и устанавливает публичный ключ Semaphore. Для
существующего Runner №10 самостоятельно выполняет подготовку:

1. Создаёт ключ SSH под `semaphore` только при отсутствии; не
   удаляет старую пару ключей.
2. Проверяет PVE HTTPS API через CA, переданный при bootstrap.
3. Если запись PVE отсутствует в `known_hosts`, считывает
   ED25519 host key по LAN и закрепляет его (TOFU).
4. Подключается штатным Ansible SSH: сначала существующим ключом,
   затем паролем root из защищённой Semaphore Variable Group №05.
   Пароль root и MQTT password передаются как секретные Ansible vars,
   а не как переменные окружения.
5. В режиме `apply` после проверки node identity добавляет
   публичный ключ Semaphore в PVE root `authorized_keys` с
   `restrict,from=<runner_ipv4>` и тестирует вход **без пароля**.

Режим `audit` не меняет файлы на PVE. На Runner при первом
подключении устанавливается штатный `sshpass` (если есть пароль №05),
создаются локальный ключ и запись `known_hosts`.
Изменения на PVE происходят только при `apply`. Установка
ключа не требует `pct destroy` или изменения bootstrap CT.

**Граница безопасности:** SSH host key legacy-Runner при первом
подключении принимается по модели TOFU. Проверка HTTPS-сертификата
PVE перед этим не доказывает независимую идентичность SSH-ключа.
Для сети с недоверенными участниками требуется заранее
проверенный SSH fingerprint, например от первичного bootstrap.
Любое последующее изменение закреплённого SSH host key
блокируется обычной проверкой OpenSSH, без обхода.

**Техническое условие:** если на существующем PVE выключен
root SSH password login и нет ранее установленного ключа,
у №10 отсутствует аутентифицированный канал для первичного
изменения root `authorized_keys`. В таком случае Ansible
останавливается с ошибкой, не снижает настройки безопасности
sshd и не использует обходные пути.

## Критерии приёмки

1. Коммит в `main`, №00 создал/обновил Survey №05 и №10 в правильном
   проекте Semaphore, не изменяя привязанные inventory/Variable Group/repo.
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
после PBS развёртывания. Cloudflare Access для HAOS/Mosquitto,
HAOS/Mosquitto deployment, NUT shutdown commissioning —
отдельные задачи, не должны запускаться побочно.

## Cloudflare Access — штатная часть №10 (редакция 11.11.2026)

У HOME `serzhan-home` проверенный management IP — `192.168.11.220`.
Адрес PVE берётся из локальной идентичности bootstrap, а не из кода задачи.
Это не означает переноса других физических серверов на тот же IP.

- `skip`: не читать и не изменять ресурсы Cloudflare.
- `audit`: проверить TLS origin, Access, Tunnel, DNS и локальное владение,
  без создания или изменения ресурсов.
- `apply`: создать отсутствующий удалённо управляемый Tunnel либо
  идемпотентно обновить существующий Tunnel с подтверждёнными DNS и route.

Публичные имена:
`<site-id>-pve.digitalhouses.vip` и
`<site-id>-pve-filebrowser.digitalhouses.vip` (без `dh-`).
Туннель — `<site-id>-pve`. Для нового Tunnel connector создаётся
на site Runner; уже существующий рабочий connector сохраняется. PVE origin: `https://<pve-ip>:8006`, с проверяемым
сертификатом от PVE CA; `noTLSVerify=false`.
Если выбран Quantum, второй маршрут — `http://<pve-ip>:8090`.

**Порядок безопасной публикации:** проверить уже существующий
self-hosted Cloudflare Access и email allowlist без Everyone/bypass;
проверить DNS на конфликты; установить/проверить HTTP Quantum;
создать Tunnel при отсутствии; записать только свои маршруты с
сохранением остальных; для нового Tunnel закрепить токен на Runner
`0600` и запустить cloudflared; дождаться Healthy; создать только
недостающие CNAME;
проверить DNS и публичный Access challenge.

**Повторное применение.** Если Tunnel `serzhan-home-pve` уже существует
и PVE DNS CNAME принадлежит именно этому Tunnel, №10 обновляет origin
PVE на `192.168.11.220:8006`, а при выбранном Quantum также
`8090`. Tunnel ID, работающий connector, Access policies и все остальные
ingress (например, Webmin) сохраняются. Для здорового Tunnel второй
connector на Runner не создаётся. Если Tunnel отсутствует, `apply`
создаёт его при свободных DNS.

**Проверка TLS:** у действующего cloudflared путь `caPool` указывает
на локальный файл CA. При переходе с другого физического PVE (`.230`)
на HOME (`.220`) прежний connector может не доверять сертификату
нового PVE. №10 сохраняет строгую проверку TLS; отключать
`noTLSVerify` нельзя. Если CA не обновлена на действующем connector,
после смены origin потребуется актуализировать CA-файл там.
Редирект Cloudflare Access подтверждает защиту входа, но не
проверяет соединение connector → PVE.

№10 **не удаляет/не пересоздаёт Tunnel, DNS или Access policies**,
не захватывает DNS другого Tunnel, не создаёт открытый Access.
Если ограничивающего Access приложения нет, публикация блокируется.
Старые `dh-...` DNS/маршруты не удаляются этим сценарием:
миграция legacy hostname — отдельная операция.

## File Browser Quantum: повторные запуски

Управляемая установка `digitalhouses-filebrowser.service` повторно
проверяется/обновляется с сохранением SQLite пользователей и паролей.
Если `filebrowser.service` уже работает на management IP и отдаёт
`/health=200`, `/api/users=401|403`, проверка из Runner позволяет
принять его без создания второго root-capable сервиса.
Если сервис неработоспособен или его конфигурация несовместима, №10
сохраняет оригинальные файлы и копию unit, останавливает старый unit и
устанавливает собственный управляемый Quantum. Его исходная база остаётся
на диске, но учётные записи в новой базе не мигрируют автоматически
через несовместимые версии; при необходимости выполняется отдельная
штатная миграция базы Quantum.

LAN порт `8090` для управляемой установки защищён отдельной
nftables-таблицей с разрешением management LAN /24. Работа Quantum
внутри LAN не доказывает готовность Cloudflare Access.
`DH_PVE_QUANTUM=skip` не меняет существующий File Browser;
при `DH_PVE_CF_ACTION=apply` новые Quantum маршруты не добавляются.

## Приёмка

Локальные проверки: YAML, Ansible syntax, ansible-lint, fixtures
маршрутов PVE/Quantum/Webmin, существующий контракт №32.
**Живой E2E новой Cloudflare Apply-ветки ещё не подтверждён.**
Повторное создание bootstrap для исправления Quantum/Cloudflare не требуется.

## Единый Cloudflare Tunnel на owner + object (11.11.2026)

Новый стандарт: **ровно один Tunnel на Site ID**. Для `serzhan-home` это
`serzhan-home`; PVE `192.168.11.220:8006`, Quantum `:8090`,
Semaphore `192.168.11.221:80` и Webmin становятся published application
routes общего Tunnel. Публичные hostname и Access policy сохраняются.

Текущие `serzhan-home-pve` и `serzhan-home-semaphore` являются
историческими сервисными Tunnel и должны быть выведены из эксплуатации.
До подтверждённого cutover запуск их `apply` из задач №08/10/32
заблокирован. Cloudflare read-only audit №10 показывает маршруты, DNS и
состав Tunnel `serzhan-home`, `serzhan-home-pve`,
`serzhan-home-semaphore`. После анализа необходимо:
объединить все ingress, проверить доступность origins с коннектора общего
Tunnel, проверить доверие к CA PVE, затем обновить CNAME. После проверки
работы всех сервисов — остановить старые cloudflared, удалить два старых
Tunnel. **Ни один ресурс Cloudflare при аудите не изменяется.**

Критерий готовности: в Cloudflare у `serzhan-home` один healthy Tunnel,
отсутствуют два устаревших, все public hostnames работают под Access и
их DNS указывают на UUID единственного Tunnel.
