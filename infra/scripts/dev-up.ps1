<#
.SYNOPSIS
    Démarre l'environnement de développement local THY (PostgreSQL+PostGIS, Redis, MinIO, Mailpit,
    collecteur OTel) et attend que chaque service soit prêt.
#>
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$composeFile = Join-Path $root "infra\docker\compose.dev.yml"

Write-Host "Demarrage des services THY (docker compose)..." -ForegroundColor Cyan
docker compose -f $composeFile up -d

Write-Host "Attente que les services soient prets..." -ForegroundColor Cyan
$services = @("postgres", "redis", "minio")
foreach ($svc in $services) {
    $cid = docker compose -f $composeFile ps -q $svc
    if (-not $cid) { throw "Service '$svc' introuvable." }
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        $status = docker inspect --format='{{.State.Health.Status}}' $cid 2>$null
        if ($status -eq "healthy") { $ready = $true; break }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) { throw "Service '$svc' n'est pas devenu 'healthy' a temps." }
    Write-Host "  $svc : pret" -ForegroundColor Green
}

Write-Host ""
Write-Host "Environnement pret :" -ForegroundColor Green
Write-Host "  PostgreSQL   -> localhost:5432 (db=thy, user=thy_migrator)"
Write-Host "  Redis        -> localhost:6379"
Write-Host "  MinIO API    -> http://localhost:9000  (console: http://localhost:9001)"
Write-Host "  Mailpit UI   -> http://localhost:8025"
Write-Host "  OTel OTLP    -> http://localhost:4318"
