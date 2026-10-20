# Project guidance for agents

## Project overview

This repository is a Go HTTP service with CI/CD, Terraform-managed Cloud.ru Evolution infrastructure, Docker Compose, Prometheus, Grafana, and Node Exporter. The source project is `hackersandslackers/golang-helloworld`; this working repository is the owner's fork.

The diploma brief defines project requirements. Treat it as requirements for the deliverable, not as authorization to create, change, or delete paid cloud resources.

## Repository map

- `main.go`, `main_test.go`: Go service and unit tests. Routes: `/`, `/healthz`, `/metrics`.
- `Dockerfile`, `compose.yaml`: container build and app/monitoring stack.
- `monitoring/`: Prometheus scrape config and Grafana provisioning/dashboard.
- `.github/workflows/ci-cd.yml`: CI checks and conditional deployment from `main` or `master`.
- `infra/evolution/main.tf`: Cloud.ru Evolution resources and outputs.
- `infra/evolution/cloud-init.yaml.tpl`: VM bootstrap (Docker, Compose, SSH key, password SSH disabled).
- `infra/evolution/deploy.ps1`, `terraform.rc`: Terraform initialization and interactive deployment wrapper/provider mirror.
- `infra/evolution/terraform.tfvars.example`: safe template only; real values belong in ignored `terraform.tfvars`.
- `README.md`, `infra/evolution/README.md`: user setup and operating instructions.

## Working conventions

- Communicate with the owner in Russian and summarize concrete changes and verification.
- Do not add explanatory comments to source/config files. Put working notes in the owner's separate local notes folder; do not copy those notes into this repository.
- Never print or commit `auth_secret`, private SSH keys, GitHub secrets, `.env`, `terraform.tfvars`, or Terraform state. Transmit deployment values only to GitHub Actions Secrets when the owner explicitly authorizes it. Do not echo secret-bearing files to the terminal.
- `terraform.tfvars` and Terraform state are ignored by Git. Keep `.terraform.lock.hcl` tracked when preparing repository changes.
- `origin` is the owner's fork; `upstream` is the original sample. Never push to `upstream`.
- Keep public project descriptions neutral and avoid conspicuous diploma wording in commit subjects or file descriptions.
- Cloud resources incur charges. Run and review `terraform plan` first; do not run `terraform apply` or `terraform destroy` without the owner's explicit approval for that operation. A request to satisfy the diploma brief alone is not approval.
- The current SSH ingress rule uses `0.0.0.0/0` to allow GitHub-hosted runners. Call this out before provisioning; SSH password login is disabled and key authentication is used.

## Useful commands

From the repository root:

```powershell
go run .
go test ./...
docker compose up --build -d
docker compose down
```

For Terraform on this host, the CLI is installed at `$env:LOCALAPPDATA\Programs\Terraform\terraform.exe` and is not currently on `PATH`. The provider mirror config is `infra/evolution/terraform.rc`. The deployment wrapper initializes Terraform and runs interactive `terraform apply`; review its plan before confirming it. To check Terraform without applying:

```powershell
$env:TF_CLI_CONFIG_FILE = (Join-Path (Get-Location) 'infra/evolution/terraform.rc')
& "$env:LOCALAPPDATA\Programs\Terraform\terraform.exe" -chdir=infra/evolution init
& "$env:LOCALAPPDATA\Programs\Terraform\terraform.exe" -chdir=infra/evolution validate
& "$env:LOCALAPPDATA\Programs\Terraform\terraform.exe" -chdir=infra/evolution plan
```

Terraform provider: `cloudru/cloud` 2.1.5. `infra/evolution/deploy.ps1` currently invokes `terraform` by command name, so it needs Terraform on `PATH` or adjustment to use the host's installed executable.

## CI/CD behavior

GitHub Actions runs on pushes and pull requests. The workflow checks `gofmt`, `golangci-lint`, `go vet`, unit tests, builds a Go binary and Docker image, and uploads both artifacts. A push to `main` or `master` deploys only when `DEPLOY_HOST`, `DEPLOY_SSH_PRIVATE_KEY`, and `GRAFANA_ADMIN_PASSWORD` are all configured. Telegram notification is optional and needs `TELEGRAM_BOT_TOKEN` plus `TELEGRAM_CHAT_ID`.

Grafana is bound to loopback on the VM and should be accessed through an SSH tunnel. Prometheus and Node Exporter are not exposed by the VM security group.

## State as of 2026-10-20

- `terraform validate` and a read-only plan succeeded before deployment: 11 resources to add, 0 to change, 0 to destroy.
- A read-only Cloud.ru query confirmed flavor `gen-2-4` is 2 vCPU / 4 GB RAM and supports `ru.AZ-1`.
- Terraform apply completed successfully and created all 11 planned resources. The VM is in `ru.AZ-1`; do not expose its address in public documentation.
- Cloud-init completed. The app and monitoring stack were deployed manually over SSH. `/healthz` and `/metrics` responded with HTTP 200; both Prometheus targets were `up`, and Grafana health reported `database: ok`.
- A generated Grafana password is stored in the ignored local `.env` on the owner host and copied to `/opt/diploma/.env` on the VM with restrictive permissions. Never display or commit either file.
- Required GitHub Actions repository secrets (`DEPLOY_HOST`, `DEPLOY_SSH_PRIVATE_KEY`, and `GRAFANA_ADMIN_PASSWORD`) are configured, as confirmed by the owner. Telegram notification secrets remain optional.
- Keep the local `terraform.tfvars` and `.env` untracked; they contain private deployment configuration.
