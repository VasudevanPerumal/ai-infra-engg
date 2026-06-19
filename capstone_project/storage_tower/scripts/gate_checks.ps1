param(
  [string]$TerraformDir = "../terraform",
  [ValidateSet("preapply", "postapply")]
  [string]$Mode = "preapply"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
Set-Location $TerraformDir

Write-Host "[Gate] Lint: terraform fmt -check -recursive"
terraform fmt -check -recursive

Write-Host "[Gate] Init: terraform init"
terraform init -upgrade

Write-Host "[Gate] Validate: terraform validate"
terraform validate

if ($Mode -eq "preapply") {
  Write-Host "[Gate] Dry-Run: terraform plan"
  terraform plan -out tfplan.preapply

  Write-Host "[Gate] Bounded Scope: only expected resources and no deletes"
  $planJson = terraform show -json tfplan.preapply | ConvertFrom-Json
  $allowedTypes = @(
    "azurerm_resource_group",
    "azurerm_virtual_network",
    "azurerm_subnet",
    "azurerm_network_security_group",
    "azurerm_subnet_network_security_group_association",
    "azurerm_public_ip",
    "azurerm_network_interface",
    "azurerm_linux_virtual_machine",
    "azurerm_storage_account",
    "azurerm_storage_container",
    "random_string"
  )

  foreach ($change in $planJson.resource_changes) {
    if ($null -eq $change) {
      continue
    }

    if ($allowedTypes -notcontains $change.type) {
      throw "Bounded scope failure: unexpected resource type '$($change.type)'"
    }

    foreach ($action in $change.change.actions) {
      if ($action -eq "delete" -or $action -eq "delete_before_replace") {
        throw "Bounded scope failure: delete action detected on '$($change.address)'"
      }
    }
  }

  Write-Host "Pre-apply gates passed."
  Write-Host "Next: terraform apply tfplan.preapply"
  Write-Host "After apply: run this script with -Mode postapply for idempotency proof"
}

if ($Mode -eq "postapply") {
  Write-Host "[Gate] Idempotency: terraform plan -detailed-exitcode"
  terraform plan -detailed-exitcode | Out-Null
  $code = $LASTEXITCODE

  if ($code -eq 0) {
    Write-Host "Post-apply idempotency passed: no changes."
    exit 0
  }

  if ($code -eq 2) {
    throw "Idempotency failure: pending changes detected after apply."
  }

  throw "terraform plan failed with exit code $code"
}
