Write-Host "=== Generando trafico intensivo (50 requests) ==="
$endpoints = @(
    "http://localhost:8001/courses",
    "http://localhost:8001/courses/1",
    "http://localhost:8001/courses/2",
    "http://localhost:8001/courses/3",
    "http://localhost:8002/catalog",
    "http://localhost:8002/firstcourse",
    "http://localhost:8001/courses/999",
    "http://localhost:8001/actuator/health",
    "http://localhost:8002/actuator/health"
)
$count = 0
for ($i = 1; $i -le 5; $i++) {
    foreach ($url in $endpoints) {
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
            $count++
            Write-Host "  [$count] $($r.StatusCode) $url"
        } catch {
            $count++
            Write-Host "  [$count] ERR $url"
        }
        Start-Sleep -Milliseconds 200
    }
}
Write-Host ""
Write-Host "=== $count requests enviados ==="
