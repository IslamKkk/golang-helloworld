# Go service with CI/CD and Cloud.ru Evolution

Небольшой HTTP-сервис на Go, подготовленный для демонстрации полного DevOps-процесса: проверки кода, сборки артефактов, развёртывания через GitHub Actions, инфраструктуры Terraform и мониторинга.

Исходный учебный проект: [hackersandslackers/golang-helloworld](https://github.com/hackersandslackers/golang-helloworld). Репозиторий распространяется по лицензии MIT; исходная лицензия сохранена в `LICENSE`.

## Состав

- Go HTTP-сервис с маршрутами `/`, `/healthz` и `/metrics`.
- Проверки `gofmt`, `golangci-lint`, `go vet` и unit-тесты `go test` в GitHub Actions.
- Сборка бинарного файла и контейнерного образа с загрузкой артефактов в GitHub Actions.
- Terraform-конфигурация сети и виртуальной машины Cloud.ru Evolution.
- Docker Compose для приложения, Jenkins, Prometheus, Grafana и Node Exporter.
- Дополнительный двухузловой K3s-кластер с NGINX reverse proxy и Cloud.ru Load Balancer.
- Jenkins pipeline для проверки кода и сборки бинарного файла.
- Уведомление в Telegram о результате workflow.

## Локальный запуск

Требуется Go 1.27.3 или новее.

```powershell
go run .
```

Сервис слушает порт `8080`. Порт можно изменить переменной окружения `PORT`, версию сборки — `APP_VERSION`.

## Локальный контейнерный стенд

Требуется Docker Compose.

```powershell
Copy-Item .env.example .env
docker compose up --build -d
```

Приложение доступно на `http://localhost/`, Grafana — на `http://localhost:3000/`. Для остановки используйте `docker compose down`.

## Инфраструктура Cloud.ru Evolution

1. Установите Terraform и проверьте предварительные условия в `infra/evolution/README.md`.
2. Скопируйте `infra/evolution/terraform.tfvars.example` в `infra/evolution/terraform.tfvars` и заполните значения в локальном файле.
3. Один развертывающий запуск: `powershell -NoProfile -ExecutionPolicy Bypass -File .\infra\evolution\deploy.ps1`. Terraform покажет план и попросит подтверждение.
4. После создания ВМ добавьте указанные ниже секреты GitHub Actions. Коммит в `main` или `master` запустит автоматическое развёртывание.
5. Для запуска двухузлового кластера включите `k3s_enabled` в локальном `terraform.tfvars`, проверьте план и ожидаемую стоимость, затем примените его вручную. Балансировщик направляет HTTP-запросы на два приватных узла K3s. Условия и оценка стоимости приведены в `infra/evolution/README.md`.

Перед коммитом в основную ветку убедитесь, что VM запущена в консоли Cloud.ru. После демонстрации VM можно остановить; диск и публичный IP продолжают тарифицироваться.

Секреты и Terraform state нельзя публиковать в Git. Файл `terraform.tfvars` и файлы состояния исключены через `.gitignore`.

## GitHub Actions secrets

Для автоматического развёртывания на основной ветке добавьте в **Settings → Secrets and variables → Actions**:

| Secret | Значение |
| --- | --- |
| `DEPLOY_HOST` | Внешний IP виртуальной машины |
| `DEPLOY_SSH_PRIVATE_KEY` | Приватный SSH-ключ пользователя, чей публичный ключ добавлен в Terraform |
| `GRAFANA_ADMIN_PASSWORD` | Пароль администратора Grafana |
| `TELEGRAM_BOT_TOKEN` | Токен Telegram-бота для уведомлений |
| `TELEGRAM_CHAT_ID` | ID чата, куда отправляются уведомления |

Для развёртывания в K3s после создания кластера добавьте в **Settings → Secrets and variables → Actions → Variables** переменные `K3S_SERVER_IP` (`10.20.0.20`) и `K3S_WORKER_IP` (`10.20.0.21`). Workflow передаёт собранный образ на обе приватные VM через основную VM и развёртывает манифест на K3s server. Пакет в GHCR остаётся закрытым.

Не отправляйте приватный SSH-ключ или Cloud.ru Key Secret в чат и не храните их в репозитории. Для веток `main` и `master` workflow публикует приложение на ВМ. Для остальных веток запускаются проверки и сохраняются артефакты.

В `ssh_source_cidr` по умолчанию используется `0.0.0.0/0`, чтобы GitHub-hosted Actions могли подключиться к ВМ. В SSH выключен вход по паролю; используется отдельный ключ, созданный для дипломной ВМ.

## Сервисы на ВМ

- Приложение: `http://<ВНЕШНИЙ_IP>/`.
- Проверка состояния: `http://<ВНЕШНИЙ_IP>/healthz`.
- Grafana доступна только локально на ВМ, порт `3000`; для просмотра используйте SSH-туннель.
- Jenkins доступен только локально на ВМ, порт `8081`; для просмотра используйте SSH-туннель.
- Prometheus и Node Exporter не открываются публично.
- При включённом K3s сервис доступен по публичному IP Cloud.ru Load Balancer. NGINX на узлах проксирует запросы к двум репликам Go-сервиса.

Пример SSH-туннеля из PowerShell: `ssh -L 3000:127.0.0.1:3000 -L 8081:127.0.0.1:8081 ubuntu@<ВНЕШНИЙ_IP>`, затем откройте `http://localhost:3000/` или `http://localhost:8081/`.

Jenkins pipeline запускает проверки и сборку Go-бинарного файла. Для настройки создайте Pipeline job типа **Pipeline script from SCM**, используйте URL репозитория `https://github.com/IslamKkk/golang-helloworld.git`, ветку `master` и файл `Jenkinsfile`.

Для первого входа получите стартовый пароль в SSH-сессии на основной VM командой `sudo docker compose -f /opt/diploma/compose.yaml exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword`. Введите его в Jenkins; не публикуйте его и не отправляйте в чат.

Для остановки ВМ и оценки оставшейся тарификации см. заметки владельца проекта и актуальные тарифы Cloud.ru. Остановка ВМ прекращает тарификацию CPU/RAM, но загрузочный диск и публичный IP тарифицируются, пока ресурсы не удалены.

## О проекте

Репозиторий содержит Go HTTP-сервис, автоматизированную сборку и развёртывание, Terraform-конфигурацию Cloud.ru и мониторинг.
