# №31 — защищённая смена общего пароля медиасервера

## Цель и статус

Отдельная задача Semaphore `31-Сменить общий пароль медиасервера`, Ansible native only; без собственных Python-скриптов.
Режим `preflight` (по умолчанию) **не меняет пароли**, но проверяет текущий владелец-логин каждой активной службы.

В режиме `apply` обновляются только: Samba owner, Jellyfin owner, Sambee owner, Radarr/Sonarr/Prowlarr Forms owner, qBittorrent owner, Filestash configuration-admin bcrypt. Filestash SMB passthrough работает через новый пароль Samba. Пароль `serzhan_admin`, Plex.com, MQTT, API-ключи интеграций не трогаются.

HTTPS-форма `/account/` устанавливается задачей №30 отдельно от логики ротации: изолированный `dh-media-account` на Node.js только проверяет HTTP/CSRF/текущий пароль, формирует root-only запрос и запускает **те же нативные Ansible tasks №31 локально на госте**. Старые Python-скрипты не используются. Никогда не вводите пароль в HTTP 80 или Semaphore Survey. До успешного live E2E ротации требуется отдельная проверка всех адаптеров; наличие формы само по себе не доказывает завершённую смену.

## Модель секретов

- Источник истины: `/<pool>/digitalhouses/credentials/<owner>.txt`, root-owned, 0600/0640. В нём остаётся **старый** пароль до успешной проверки **всех** новых логинов.
- Одноразовый локальный запрос: `/<pool>/digitalhouses/credentials/.dh-media-password-request`, root:root 0600, одна строка `password=<new 6–8 alphanumeric>`.
- Журнал возобновления: `/<pool>/digitalhouses/credentials/.dh-media-password-rotation.json`, root:root 0600, содержит старый/новый пароли. Не переносить в журналы, репозитории, HTTP, stdout или Semaphore.
- Блокировка: `/<pool>/digitalhouses/credentials/.dh-media-password-rotation.lock` — атомарный `mkdir` 0700. При конкурирующем запуске смена не стартует.
- Операции с паролями используют `no_log: true`; локальные API `127.0.0.1`, а qBittorrent проверяется через LAN, где не действует loopback bypass.

## Приёмка / этапы

1. Сначала выполните №31 `preflight` и убедитесь в `MEDIA31_PREFLIGHT=PASS`.
2. Тестируйте `apply` **с тестовой учётной записью/VM и тестовым новым паролем**, проверяя прерывание после нескольких адаптеров и продолжение. Не менять производственный пароль до успешного теста.
3. При ручном вводе нового пароля оператором используйте только root Shell **гостевой VM**, интерактивный скрытый ввод. Значение нельзя передавать через аргументы, переменные окружения процесса, историю Shell, Git или Semaphore.
4. После создания защищённого запроса запускают №31 `apply`. Все новые логины проверяются до записи основного credential TXT. Запрос и журнал удаляются только после подтверждения.
5. При сбое код возвращает `MEDIA31_ROTATION_INCOMPLETE`, **не откатывает молча** уже изменённые сервисы. Обычная задача №30 отказывается от дальнейшей настройки при наличии журнала/lock. После устранения причины повторить №31 `apply`: каждый адаптер принимает уже сменённый пароль и идёт дальше. При внезапном убийстве процесса `mkdir`-lock может сохраниться: сначала убедиться, что №31 нигде не запущена, затем диагностировать и устранить lock администратором. Не удалять журнал.

## Ручной ввод на госте (только root, после стендовой приёмки)

```sh
umask 077
read -r -s -p 'Новый пароль (6–8 символов A-Za-z0-9): ' NEWPW; printf '\n'
printf 'password=%s\n' "$NEWPW" > /serzhan-pool/digitalhouses/credentials/.dh-media-password-request
unset NEWPW
chmod 0600 /serzhan-pool/digitalhouses/credentials/.dh-media-password-request
```

Это только пример передачи через локальный защищённый файл, не веб-обработчик и не команда с секретом в argv.

## Проверки

- `ansible-playbook -i localhost, -c local tests/media31-native-password-rotation.yml`
- `ansible-playbook -i localhost, -c local --syntax-check playbooks/media-password-rotate.yml`
- `ansible-lint playbooks/media-password-rotate.yml tasks/media31-password-*.yml`
- №31 `preflight` на реальной VM: проверяет логины, не изменяет их.
- №31 `apply` на реальной VM **отложен**, пока не будет согласован новый пароль и успешно проверен стендовый E2E.

## Ограничения

- Это **forward-resume**, а не автоматический rollback: при проблемах операция не объявляется успешной.
- В случае потери доступа из-за частичной смены может понадобиться ручное восстановление из защищённого журнала.
- Пока нет завершённого live `apply` E2E, реализацию нельзя считать готовой для произвольного использования клиентом.
