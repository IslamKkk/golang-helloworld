$ErrorActionPreference = "Stop"

Push-Location $PSScriptRoot
try {
  $env:TF_CLI_CONFIG_FILE = Join-Path $PSScriptRoot "terraform.rc"

  terraform init
  if ($LASTEXITCODE -ne 0) {
    throw "terraform init failed with exit code $LASTEXITCODE"
  }

  terraform apply
  if ($LASTEXITCODE -ne 0) {
    throw "terraform apply failed with exit code $LASTEXITCODE"
  }
} finally {
  Pop-Location
}
