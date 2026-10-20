$ErrorActionPreference = "Stop"

$terraformCommand = Get-Command terraform -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($terraformCommand) {
  $terraformPath = $terraformCommand.Source
} else {
  $terraformPath = Join-Path $env:LOCALAPPDATA "Programs\Terraform\terraform.exe"
}

if (-not (Test-Path -LiteralPath $terraformPath -PathType Leaf)) {
  throw "Terraform CLI was not found. Install it or add it to PATH. Checked: $terraformPath"
}

Push-Location $PSScriptRoot
try {
  $previousTerraformConfig = $env:TF_CLI_CONFIG_FILE
  $env:TF_CLI_CONFIG_FILE = Join-Path $PSScriptRoot "terraform.rc"

  & $terraformPath init
  if ($LASTEXITCODE -ne 0) {
    throw "terraform init failed with exit code $LASTEXITCODE"
  }

  & $terraformPath apply
  if ($LASTEXITCODE -ne 0) {
    throw "terraform apply failed with exit code $LASTEXITCODE"
  }
} finally {
  $env:TF_CLI_CONFIG_FILE = $previousTerraformConfig
  Pop-Location
}
