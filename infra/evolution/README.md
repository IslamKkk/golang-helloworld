# Cloud.ru Evolution

Terraform создаёт VPC, подсеть, группу безопасности, загрузочный диск, сетевой интерфейс с публичным IP и виртуальную машину Ubuntu 22.04. Cloud-init устанавливает Docker и Compose, добавляет ваш публичный SSH-ключ и отключает вход по паролю.

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

Создайте сервисный аккаунт уровня «Проект». Для описанных Terraform-ресурсов назначьте сервисную роль `eiv.admin` в Virtual Machines и `vpc.admin` в Evolution VPC в этом проекте. Не выдавайте права на организацию целиком. `eiv.admin` нужен в том числе для аренды публичного IP, `vpc.admin` — для создания и удаления VPC.

## Настройка провайдера

Cloud.ru публикует Terraform provider через собственное зеркало. `deploy.ps1` автоматически настраивает его через `terraform.rc`. Официальная инструкция: [быстрый старт Terraform для Evolution](https://cloud.ru/docs/terraform-evolution/ug/topics/quickstart).

## Подготовка параметров

Скопируйте пример в локальный файл:

```powershell
Copy-Item infra/evolution/terraform.tfvars.example infra/evolution/terraform.tfvars
```

Укажите ID проекта, Key ID и Key Secret, путь к публичному SSH-ключу и существующее в проекте имя флейвора на 2 vCPU и 4 ГБ RAM. Не публикуйте `terraform.tfvars` и `terraform.tfstate`.

Key ID и Key Secret создаются для сервисного аккаунта Cloud.ru. Сервисный аккаунт выбирается уровня «Проект» для одного проекта; ему нужны права управления Compute и VPC. Значения храните только в `terraform.tfvars` на компьютере.

Для SSH в Terraform по умолчанию открывается порт 22 для IPv4, чтобы GitHub-hosted Actions могли выполнять deployment. Доступ защищается SSH-ключом; парольный SSH-вход выключен. Если указать в `ssh_source_cidr` свой адрес в формате `x.x.x.x/32`, SSH с GitHub-hosted runners будет заблокирован.

## Создание ресурсов

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\infra\evolution\deploy.ps1
```

Terraform покажет план ресурсов и запросит подтверждение перед созданием. Проверьте план и ожидаемую стоимость в консоли Cloud.ru. Terraform выведет внешний IP ВМ. Он понадобится в GitHub Actions secret `DEPLOY_HOST`.

Перед deployment ВМ должна быть запущена: SSH workflow подключается к ней по публичному IP. Запускайте и останавливайте её через консоль Cloud.ru. При остановке CPU/RAM не тарифицируются, но диск и публичный IP продолжают тарифицироваться; для длинных перерывов удалите ресурсы через `terraform destroy`.

## Удаление ресурсов

Когда проект больше не нужен, выполните из корня репозитория:

```powershell
terraform destroy -chdir=infra/evolution
```

Проверьте итоговый план удаления: должны удалиться VM, публичный IP, диск, интерфейс, группа безопасности, подсеть и VPC.
