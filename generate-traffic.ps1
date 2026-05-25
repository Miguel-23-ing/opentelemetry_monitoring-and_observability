Write-Host "=== Generating traffic ==="

for ($i = 1; $i -le 10; $i++) {
    Write-Host "Request $i : GET /courses"
    try { Invoke-WebRequest -Uri "http://localhost:8001/courses" -UseBasicParsing | Out-Null; Write-Host "  OK" } catch { Write-Host "  FAIL: $_" }
    Start-Sleep -Milliseconds 500
}

for ($i = 1; $i -le 5; $i++) {
    Write-Host "Request $i : GET /catalog"
    try { Invoke-WebRequest -Uri "http://localhost:8002/catalog" -UseBasicParsing | Out-Null; Write-Host "  OK" } catch { Write-Host "  FAIL: $_" }
    Start-Sleep -Milliseconds 500
}

for ($i = 1; $i -le 3; $i++) {
    Write-Host "Request $i : GET /courses/1"
    try { Invoke-WebRequest -Uri "http://localhost:8001/courses/1" -UseBasicParsing | Out-Null; Write-Host "  OK" } catch { Write-Host "  FAIL: $_" }
    Start-Sleep -Milliseconds 300
}

Write-Host "Request: GET /courses/999 (should be 404 or empty)"
try { Invoke-WebRequest -Uri "http://localhost:8001/courses/999" -UseBasicParsing | Out-Null; Write-Host "  OK" } catch { Write-Host "  Response: $_" }

Write-Host ""
Write-Host "=== Traffic generation complete ==="
Write-Host "Total: 19 requests sent"
Write-Host ""
Write-Host "Verify at:"
Write-Host "  Jaeger:      http://localhost:16686"
Write-Host "  Prometheus:  http://localhost:9090"
Write-Host "  Grafana:     http://localhost:3000 (admin/admin)"
Write-Host "  Kibana:      http://localhost:5601"
