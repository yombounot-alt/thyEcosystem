<#
.SYNOPSIS
    Arrête l'environnement de développement local THY. Les volumes de données sont conservés
    (utiliser dev-reset-db.ps1 pour repartir d'une base vide).
#>
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$composeFile = Join-Path $root "infra\docker\compose.dev.yml"

docker compose -f $composeFile down
Write-Host "Environnement arrete (volumes conserves)." -ForegroundColor Yellow
