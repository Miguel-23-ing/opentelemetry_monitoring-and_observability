# =============================================================================
# generate-errors.ps1
# Modifica temporalmente la alerta HighErrorRate para contar 4xx+5xx con
# umbral del 5%, luego bombardea con 404s para dispararla.
#
# Flujo:
#   1. Ejecutar este script
#   2. Abrir http://localhost:9090/alerts
#   3. ~30s  → HighErrorRate pasa a PENDING (amarillo)
#   4. ~2min → HighErrorRate pasa a FIRING (rojo)
#   5. Ctrl+C para detener
#   6. Esperar ~5 min → vuelve a INACTIVE sola
#   (o ejecutar restore-alerts.ps1 para restaurar inmediatamente)
# =============================================================================

$ErrorActionPreference = "SilentlyContinue"

Write-Host ""
Write-Host "================================================" -ForegroundColor Yellow
Write-Host "  GENERADOR DE ERRORES - ALERTA HighErrorRate  " -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow
Write-Host ""

# --- Paso 1: Modificar regla para contar 4xx+5xx con umbral 5% ---
$alertFile = ".\prometheus_alert_rules.yml"
$content = [System.IO.File]::ReadAllText((Resolve-Path $alertFile), [System.Text.Encoding]::UTF8)

# Backup
[System.IO.File]::WriteAllText("$alertFile.bak", $content, [System.Text.UTF8Encoding]::new($false))

# Cambiar: solo 5xx con >10%  →  4xx+5xx con >5%
$modified = $content `
    -replace 'http_response_status_code=~"5\.\."', 'http_response_status_code=~"[45].."' `
    -replace '\) > 0\.1', ') > 0.05'

[System.IO.File]::WriteAllText((Resolve-Path $alertFile), $modified, [System.Text.UTF8Encoding]::new($false))
Write-Host "[1/3] Regla modificada: ahora cuenta 4xx+5xx con umbral 5%" -ForegroundColor Green

# --- Paso 2: Recargar Prometheus ---
try {
    Invoke-WebRequest "http://localhost:9090/-/reload" -Method POST -UseBasicParsing -TimeoutSec 5 | Out-Null
    Write-Host "[2/3] Prometheus recargado" -ForegroundColor Green
} catch {
    docker restart prometheus 2>$null | Out-Null
    Start-Sleep 6
    Write-Host "[2/3] Prometheus reiniciado" -ForegroundColor Green
}
Start-Sleep 3

# --- Paso 3: Bombardear con 404s (3 errores por cada 1 ok = 75% error) ---
Write-Host "[3/3] Enviando requests: 1 OK + 3 errores (404) por ciclo" -ForegroundColor Green
Write-Host ""
Write-Host "Abre: http://localhost:9090/alerts" -ForegroundColor Cyan
Write-Host "  ~30s  → PENDING  |  ~2min → FIRING" -ForegroundColor Yellow
Write-Host "  Ctrl+C para detener y luego ejecuta restore-alerts.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host " Req | OK  | ERR | Tasa" -ForegroundColor White
Write-Host "-----|-----|-----|------" -ForegroundColor White

$total = 0
$errs  = 0

try {
    while ($true) {
        # 1 OK
        try { Invoke-WebRequest "http://localhost:8001/courses/1" -UseBasicParsing -TimeoutSec 3 | Out-Null } catch {}
        $total++

        # 3 errores garantizados (404)
        foreach ($id in @(999, 888, 777)) {
            try { Invoke-WebRequest "http://localhost:8001/courses/$id" -UseBasicParsing -TimeoutSec 3 | Out-Null }
            catch { $errs++ }
            $total++
        }

        $rate  = if ($total -gt 0) { [math]::Round($errs / $total * 100, 1) } else { 0 }
        $color = if ($rate -gt 30) { "Red" } elseif ($rate -gt 5) { "Yellow" } else { "White" }
        Write-Host ("{0,4} | {1,3} | {2,3} | {3}%" -f $total, ($total - $errs), $errs, $rate) -ForegroundColor $color

        Start-Sleep 1
    }
} finally {
    Write-Host ""
    Write-Host "Script detenido. Para restaurar la regla original:" -ForegroundColor Yellow
    Write-Host "  powershell -ExecutionPolicy Bypass -File restore-alerts.ps1" -ForegroundColor White
}
