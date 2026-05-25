# =============================================================================
# restore-alerts.ps1
# Restaura los umbrales originales de alertas después de ejecutar trigger-alerts.ps1
# =============================================================================

Write-Host ""
Write-Host "=== RESTAURANDO UMBRALES ORIGINALES ===" -ForegroundColor Yellow

$alertFile = ".\prometheus_alert_rules.yml"
$backupFile = "$alertFile.bak"

if (Test-Path $backupFile) {
    Copy-Item $backupFile $alertFile -Force
    Remove-Item $backupFile -Force
    Write-Host "[OK] prometheus_alert_rules.yml restaurado desde backup" -ForegroundColor Green
} else {
    # Restaurar manualmente si no hay backup
    $content = Get-Content $alertFile -Raw
    $restored = $content `
        -replace '\) > 0\.05', ') > 0.1' `
        -replace 'http_response_status_code=~"\[45\]\.\."', 'http_response_status_code=~"5.."'
    [System.IO.File]::WriteAllText((Resolve-Path $alertFile), $restored, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[OK] Umbral y filtro de errores restaurados" -ForegroundColor Green
}

# Recargar Prometheus
Write-Host "Recargando Prometheus..." -ForegroundColor Cyan
try {
    Invoke-WebRequest "http://localhost:9090/-/reload" -Method POST -UseBasicParsing | Out-Null
    Write-Host "[OK] Prometheus recargado" -ForegroundColor Green
} catch {
    docker restart prometheus | Out-Null
    Start-Sleep 5
    Write-Host "[OK] Prometheus reiniciado" -ForegroundColor Green
}

Write-Host ""
Write-Host "Umbrales restaurados. Las alertas volverán a Inactive en ~2 minutos." -ForegroundColor Cyan
Write-Host "Verifica en: http://localhost:9090/alerts" -ForegroundColor White
