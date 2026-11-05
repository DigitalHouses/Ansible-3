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
  `digitalhouses_pve_agent-v0.5.72` (installer SHA256 проверяется),
  MQTT host и credentials из №05. Уже установленная версия агента
  сохраняется: №10 не понижает её при повторном запуске.
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

## Автоматическое подключение существующего Runner (CT1231)

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
после PBS развёртывания. Cloudflare Access для PVE/Quantum,
HAOS/Mosquitto deployment, NUT shutdown commissioning —
отдельные задачи, не должны запускаться побочно.
