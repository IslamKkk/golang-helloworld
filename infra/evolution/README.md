# Cloud.ru Evolution

Terraform создаёт VPC, подсеть, группу безопасности, загрузочный диск, сетевой интерфейс с публичным IP и виртуальную машину Ubuntu 22.04. Cloud-init устанавливает Docker и Compose, добавляет ваш публичный SSH-ключ и отключает вход по паролю. Дополнительный двухузловой кластер K3s и публичный Cloud.ru Load Balancer включаются отдельно переменной `k3s_enabled`.

## Требования

- Проект Cloud.ru Evolution с доступной квотой и проверенным лимитом расходов.
- Сервисный аккаунт уровня «Проект» и его Key ID / Key Secret.
- Terraform для Windows.
- SSH-ключ Ed25519. В Terraform передаётся путь только к `.pub` файлу.

Создайте отдельную пару ключей для дипломной ВМ в PowerShell:

```powershell
ssh-keygen -t ed25519 -a 64 -f "$env:USERPROFILE\.ssh\diplom-evolution" -C "diplom-evolution"
```

Установите пустую passphrase для этого отдельного ключа, чтобы GitHub Actions мог использовать его без интерактивного запроса. Закрытый файл `diplom-evolution` останется на вашем компьютере и будет сохранён как GitHub Actions secret; в Terraform указывается только `diplom-evolution.pub`.

Создайте сервисный аккаунт уровня «Проект». Для основной VM назначьте сервисные роли `eiv.admin` в Virtual Machines и `vpc.admin` в Evolution VPC в этом проекте. Для включённого K3s добавьте `nlb.admin` в Load Balancer. Не выдавайте права на организацию целиком. `eiv.admin` нужен для Compute и SNAT-шлюза, `vpc.admin` — для создания и удаления VPC.

## Настройка провайдера

Cloud.ru публикует Terraform provider через собственное зеркало. `deploy.ps1` автоматически настраивает его через `terraform.rc`. Официальная инструкция: [быстрый старт Terraform для Evolution](https://cloud.ru/docs/terraform-evolution/ug/topics/quickstart).

## Подготовка параметров

Скопируйте пример в локальный файл:

```powershell
Copy-Item infra/evolution/terraform.tfvars.example infra/evolution/terraform.tfvars
```

Укажите ID проекта, Key ID и Key Secret, путь к публичному SSH-ключу и существующее в проекте имя флейвора на 2 vCPU и 4 ГБ RAM. Не публикуйте `terraform.tfvars` и `terraform.tfstate`.

Для двухузлового кластера создайте локальный секрет K3s и включите его в локальном `terraform.tfvars`:

```powershell
$tfvarsPath = 'infra/evolution/terraform.tfvars'
$tfvars = [System.IO.File]::ReadAllText($tfvarsPath)
if ($tfvars -notmatch '(?m)^\s*k3s_token\s*=') {
    $bytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $k3sToken = [Convert]::ToHexString($bytes).ToLowerInvariant()
    $tfvars += "`nk3s_token = `"$k3sToken`"`n"
    Remove-Variable k3sToken, bytes
}
if ($tfvars -match '(?m)^\s*k3s_enabled\s*=') {
    $tfvars = [regex]::Replace($tfvars, '(?m)^\s*k3s_enabled\s*=.*$', 'k3s_enabled = true')
} else {
    $tfvars += "`nk3s_enabled = true`n"
}
[System.IO.File]::WriteAllText($tfvarsPath, $tfvars, [System.Text.UTF8Encoding]::new($false))
Remove-Variable tfvars
```

Эти строки предназначены только для игнорируемого `terraform.tfvars`. Не сохраняйте токен в репозитории и не отправляйте его в чат. Публичная часть приложения кластера использует GitHub Container Registry.

Key ID и Key Secret создаются для сервисного аккаунта Cloud.ru. Сервисный аккаунт выбирается уровня «Проект» для одного проекта; ему нужны права управления Compute и VPC, а для балансировщика — сервисная роль `nlb.admin`. Значения храните только в `terraform.tfvars` на компьютере.

Для SSH в Terraform по умолчанию открывается порт 22 для IPv4, чтобы GitHub-hosted Actions могли выполнять deployment. Доступ защищается SSH-ключом; парольный SSH-вход выключен. Если указать в `ssh_source_cidr` свой адрес в формате `x.x.x.x/32`, SSH с GitHub-hosted runners будет заблокирован.

## Создание ресурсов

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\infra\evolution\deploy.ps1
```

Terraform покажет план ресурсов и запросит подтверждение перед созданием. Проверьте план и ожидаемую стоимость в консоли Cloud.ru. Terraform выведет внешний IP ВМ. Он понадобится в GitHub Actions secret `DEPLOY_HOST`.

Перед deployment ВМ должна быть запущена: SSH workflow подключается к ней по публичному IP. Запускайте и останавливайте её через консоль Cloud.ru. При остановке CPU/RAM не тарифицируются, но диск и публичный IP продолжают тарифицироваться; для длинных перерывов удалите ресурсы через `terraform destroy`.

План кластера можно проверить отдельно без создания ресурсов:

```powershell
$env:TF_CLI_CONFIG_FILE = (Join-Path (Get-Location) 'infra/evolution/terraform.rc')
& "$env:LOCALAPPDATA\Programs\Terraform\terraform.exe" -chdir=infra/evolution plan -var="k3s_enabled=true"
```

План должен включать две приватные VM, диски, правила сети, целевую группу и балансировщик. Проверьте план и текущий тариф Cloud.ru перед созданием.

После создания добавьте в **Settings → Secrets and variables → Actions → Variables** переменные `K3S_SERVER_IP` со значением `10.20.0.20` и `K3S_WORKER_IP` со значением `10.20.0.21`. Push в основную ветку продолжит развёртывать Compose на исходную VM и дополнительно передаст собранный образ на оба узла через SSH bastion, загрузит его в containerd и обновит кластер K3s. Пакет в GitHub Container Registry остаётся закрытым.

Кластер использует две VM `gen-2-4` по 2 vCPU и 4 ГБ RAM, SSD по 30 ГБ, публичный SNAT-шлюз и Cloud.ru Load Balancer. По [тарифам Compute](https://cloud.ru/documents/tariffs/evolution/evolution-compute) на 22 октября 2026 года вычисления двух VM стоят около 5,84 ₽/час; загрузочные диски по 30 ГБ стоят около 0,94 ₽/час согласно [правилам тарификации VM](https://cloud.ru/docs/virtual-machines/ug/topics/pricing). Минимальная ресурсная единица и публичный адрес балансировщика стоят около 1,01 ₽/час по [тарифу Load Balancer](https://cloud.ru/documents/tariffs/evolution/load-balancer), SNAT-шлюз — около 0,21 ₽/час по тарифу Compute. Итого — около 8,00 ₽/час, или 5 759 ₽ за 720 часов непрерывной работы. При выключенных VM сохраняются примерно 2,15 ₽/час за диски, балансировщик и SNAT-шлюз. Трафик оплачивается отдельно. Чтобы перестать платить за кластер и сетевые сервисы, установите `k3s_enabled = false` и примените проверенный Terraform-план: кластерные VM, диски, балансировщик и SNAT-шлюз будут удалены, основная VM останется.

## Удаление ресурсов

Когда проект больше не нужен, выполните из корня репозитория:

```powershell
terraform destroy -chdir=infra/evolution
```

Проверьте итоговый план удаления: должны удалиться VM, публичный IP, диск, интерфейс, группа безопасности, подсеть и VPC.
