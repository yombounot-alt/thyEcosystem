<#
.SYNOPSIS
    Réinitialise la base PostgreSQL locale (supprime le volume de données puis redémarre).
    À utiliser après un changement de schéma incompatible en développement, jamais en staging/prod.
#>
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$composeFile = Join-Path $root "infra\docker\compose.dev.yml"

Write-Host "Cette action supprime TOUTES les donnees locales de PostgreSQL (dev uniquement)." -ForegroundColor Red
$confirm = Read-Host "Taper 'reset' pour confirmer"
if ($confirm -ne "reset") { Write-Host "Annule."; exit 0 }

docker compose -f $composeFile stop postgres
docker compose -f $composeFile rm -f postgres
docker volume rm thy-dev_pg_data -f

& (Join-Path $PSScriptRoot "dev-up.ps1")
