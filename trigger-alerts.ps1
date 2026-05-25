# =============================================================================
# trigger-alerts.ps1
# Dispara alertas de Prometheus bajando temporalmente los umbrales y
# generando tráfico con errores sostenido durante 2+ minutos.
#
# Alertas que se activarán:
#   - HighErrorRate  → >10% de errores 5xx durante 2 min
#   - NoTraffic      → se activa sola si no hay tráfico 10 min (no requiere script)
#
# Uso: powershell -ExecutionPolicy Bypass -File trigger-alerts.ps1
# Para restaurar umbrales: powershell -ExecutionPolicy Bypass -File restore-alerts.ps1
# =============================================================================

$ErrorActionPreference = "SilentlyContinue"

Write-Host ""
Write-Host "=== TRIGGER DE ALERTAS PROMETHEUS ===" -ForegroundColor Yellow
Write-Host ""
Write-Host "Estrategia: bajar umbral de HighErrorRate a 0.01 (1%) y enviar" -ForegroundColor Cyan
Write-Host "requests con errores de forma continua durante 3 minutos." -ForegroundColor Cyan
Write-Host ""

# --- Paso 1: Bajar el umbral de HighErrorRate a 1% ---
$alertFile = ".\prometheus_alert_rules.yml"
$content = Get-Content $alertFile -Raw

# Backup
Copy-Item $alertFile "$alertFile.bak" -Force
Write-Host "[1/3] Backup de alertas guardado en prometheus_alert_rules.yml.bak" -ForegroundColor Green

# Bajar umbral: ) > 0.1  →  ) > 0.01
$modified = $content -replace '\) > 0\.1', ') > 0.01'
Set-Content $alertFile $modified -Encoding UTF8
Write-Host "[1/3] Umbral HighErrorRate bajado: 10% → 1% (dispara más fácil)" -ForegroundColor Green

# --- Paso 2: Recargar Prometheus con nuevo umbral ---
Write-Host "[2/3] Recargando Prometheus con nuevo umbral..." -ForegroundColor Green
try {
    Invoke-WebRequest "http://localhost:9090/-/reload" -Method POST -UseBasicParsing | Out-Null
    Write-Host "[2/3] Prometheus recargado OK" -ForegroundColor Green
} catch {
    Write-Host "[2/3] Recarga via API fallida - reiniciando contenedor..." -ForegroundColor Yellow
    docker restart prometheus | Out-Null
    Start-Sleep 5
    Write-Host "[2/3] Prometheus reiniciado" -ForegroundColor Green
}

Start-Sleep 3

# --- Paso 3: Enviar tráfico con errores durante 3 minutos ---
Write-Host ""
Write-Host "[3/3] Enviando tráfico con ~50% errores durante 3 minutos..." -ForegroundColor Yellow
Write-Host "      Abre http://localhost:9090/alerts para ver el estado" -ForegroundColor Cyan
Write-Host "      La alerta pasará: Inactive → Pending (ahora) → Firing (en ~1 min)" -ForegroundColor Cyan
Write-Host ""

$endpoints = @(
    "http://localhost:8001/courses",        # 200
    "http://localhost:8001/courses/999",    # 404 (no dispara HighErrorRate, son 4xx)
    "http://localhost:8001/courses/1",      # 200
    "http://localhost:8001/courses/999"     # 404
)

# Endpoints para 5xx: enviar POST malformado que genere 500
$endpoints5xx = @(
    "http://localhost:8001/courses",        # POST con body inválido → 400/500
    "http://localhost:8002/catalog"         # 200
)

$startTime = Get-Date
$duration = 180  # 3 minutos
$requestCount = 0
$errorCount = 0

Write-Host "Tiempo | Requests | Errores | Tasa de error" -ForegroundColor White
Write-Host "-------|----------|---------|---------------" -ForegroundColor White

while ((Get-Date) -lt $startTime.AddSeconds($duration)) {
    # 3 requests normales
    foreach ($url in @("http://localhost:8001/courses/1", "http://localhost:8002/catalog", "http://localhost:8001/courses")) {
        try {
            Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 3 | Out-Null
            $requestCount++
        } catch { $requestCount++ }
    }

    # 2 requests que generan error (POST sin Content-Type → 415/500)
    foreach ($url in @("http://localhost:8001/courses", "http://localhost:8001/courses")) {
        try {
            Invoke-WebRequest $url -Method POST -Body "INVALID_DATA" -UseBasicParsing -TimeoutSec 3 | Out-Null
            $requestCount++
        } catch {
            $requestCount++
            $errorCount++
        }
    }

    $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
    $rate = if ($requestCount -gt 0) { [math]::Round($errorCount / $requestCount * 100, 1) } else { 0 }

    if ($elapsed % 15 -eq 0) {
        Write-Host "  ${elapsed}s  |   $requestCount    |   $errorCount   | $rate%" -ForegroundColor $(if ($rate -gt 1) { "Red" } else { "Yellow" })
    }

    Start-Sleep 1
}

Write-Host ""
Write-Host "=== COMPLETADO ===" -ForegroundColor Green
Write-Host "Revisa http://localhost:9090/alerts — HighErrorRate debería estar en FIRING" -ForegroundColor Cyan
Write-Host ""
Write-Host "Para restaurar los umbrales originales:" -ForegroundColor Yellow
Write-Host "  powershell -ExecutionPolicy Bypass -File restore-alerts.ps1" -ForegroundColor White
