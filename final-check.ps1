Write-Host "======================================================="
Write-Host " VERIFICACION FINAL COMPLETA - FutureX OpenTelemetry"
Write-Host "======================================================="

$OK = "[OK]"
$FAIL = "[FAIL]"

# ===================== 1. INFRAESTRUCTURA =====================
Write-Host ""
Write-Host "--- 1. INFRAESTRUCTURA ---"

$containers = @("elasticsearch","futurex-mysql","grafana","jaeger","kibana","logstash","otel-collector","prometheus")
foreach ($c in $containers) {
    $st = (docker inspect --format "{{.State.Status}}" $c 2>&1)
    $health = (docker inspect --format "{{.State.Health.Status}}" $c 2>&1)
    $label = if ($health -match "healthy|none") { $OK } else { $FAIL }
    Write-Host "  $label $c -> status=$st health=$health"
}

# Prometheus target
$targets = (Invoke-WebRequest "http://localhost:9090/api/v1/targets" -UseBasicParsing | ConvertFrom-Json).data.activeTargets
$up = $targets | Where-Object { $_.health -eq "up" }
Write-Host "  $OK Prometheus targets UP: $($up.Count)/$($targets.Count)"

# ===================== 2. METRICAS PROMETHEUS =====================
Write-Host ""
Write-Host "--- 2. METRICAS PROMETHEUS ---"

$allM = (Invoke-WebRequest "http://localhost:9090/api/v1/label/__name__/values" -UseBasicParsing | ConvertFrom-Json).data
$otelM = $allM | Where-Object { $_ -like "otel_*" } | Sort-Object
Write-Host "  $OK Metricas otel_*: $($otelM.Count)"

# Verificar metricas clave una a una
$keyMetrics = @(
    "otel_http_server_request_duration_seconds_count",
    "otel_http_server_request_duration_seconds_sum",
    "otel_http_server_request_duration_seconds_bucket",
    "otel_jvm_cpu_recent_utilization_ratio",
    "otel_jvm_memory_used_bytes",
    "otel_jvm_memory_committed_bytes",
    "otel_jvm_thread_count",
    "otel_db_client_connections_usage"
)
foreach ($m in $keyMetrics) {
    $exists = $otelM -contains $m
    $label = if ($exists) { $OK } else { $FAIL }
    Write-Host "  $label $m"
}

# ===================== 3. LABELS REALES =====================
Write-Host ""
Write-Host "--- 3. LABELS REALES (HTTP) ---"
$httpSeries = (Invoke-WebRequest "http://localhost:9090/api/v1/query?query=otel_http_server_request_duration_seconds_count" -UseBasicParsing | ConvertFrom-Json).data.result
Write-Host "  $OK Total series HTTP: $($httpSeries.Count)"
$routes = $httpSeries | ForEach-Object { $_.metric.http_route } | Sort-Object -Unique
Write-Host "  $OK Rutas reales: $($routes -join ', ')"
$services = $httpSeries | ForEach-Object { $_.metric.exported_job } | Sort-Object -Unique
Write-Host "  $OK Servicios: $($services -join ', ')"
$statuses = $httpSeries | ForEach-Object { $_.metric.http_response_status_code } | Sort-Object -Unique
Write-Host "  $OK Status codes: $($statuses -join ', ')"

# ===================== 4. QUERIES CRITICOS =====================
Write-Host ""
Write-Host "--- 4. QUERIES PROMETHEUS (verificacion real) ---"

$queries = @{
    "Req/min total"        = "sum(rate(otel_http_server_request_duration_seconds_count[1m]))*60"
    "Error rate %"         = "(sum(rate(otel_http_server_request_duration_seconds_count{http_response_status_code=~`"[45]..`"}[5m]))/sum(rate(otel_http_server_request_duration_seconds_count[5m])))*100"
    "P95 latencia ms"      = "histogram_quantile(0.95,sum(rate(otel_http_server_request_duration_seconds_bucket[5m]))by(le))*1000"
    "CPU catalog"          = "otel_jvm_cpu_recent_utilization_ratio{exported_job=`"fx-catalog-service`"}*100"
    "CPU course"           = "otel_jvm_cpu_recent_utilization_ratio{exported_job=`"fx-course-service`"}*100"
    "Heap course MB"       = "sum(otel_jvm_memory_used_bytes{jvm_memory_type=`"heap`",exported_job=`"fx-course-service`"})/1024/1024"
    "Threads course"       = "otel_jvm_thread_count{exported_job=`"fx-course-service`"}"
    "DB pool idle"         = "otel_db_client_connections_usage{state=`"idle`"}"
}
foreach ($name in $queries.Keys) {
    $q = [uri]::EscapeDataString($queries[$name])
    $r = (Invoke-WebRequest "http://localhost:9090/api/v1/query?query=$q" -UseBasicParsing | ConvertFrom-Json).data.result
    if ($r.Count -gt 0) {
        $val = [math]::Round([double]$r[0].value[1], 2)
        Write-Host "  $OK $name = $val"
    } else {
        Write-Host "  $FAIL $name = (no data)"
    }
}

# ===================== 5. ELASTICSEARCH =====================
Write-Host ""
Write-Host "--- 5. ELASTICSEARCH & LOGSTASH ---"

$cnt = (Invoke-WebRequest "http://localhost:9200/otel-logs-*/_count" -UseBasicParsing | ConvertFrom-Json).count
Write-Host "  $OK Total docs ES: $cnt"

$body = '{"size":0,"aggs":{"by_svc":{"terms":{"field":"service.name.keyword","size":10}},"by_level":{"terms":{"field":"log.level.keyword","size":10}},"with_trace":{"filter":{"bool":{"must":[{"exists":{"field":"traceId"}}],"must_not":[{"term":{"traceId":""}}]}}}}}'
$aggs = (Invoke-WebRequest "http://localhost:9200/otel-logs-*/_search" -Method POST -Body $body -ContentType "application/json" -UseBasicParsing | ConvertFrom-Json).aggregations

foreach ($b in $aggs.by_svc.buckets) { Write-Host "  $OK Logs $($b.key): $($b.doc_count) docs" }
foreach ($b in $aggs.by_level.buckets) { Write-Host "  $OK Level $($b.key): $($b.doc_count) docs" }
Write-Host "  $OK Docs con traceId real: $($aggs.with_trace.doc_count)"

# Verificar campos clave en un documento real
$sampleBody = '{"size":1,"query":{"bool":{"must":[{"exists":{"field":"traceId"}}],"must_not":[{"term":{"traceId":""}}]}}}'
$sample = (Invoke-WebRequest "http://localhost:9200/otel-logs-*/_search" -Method POST -Body $sampleBody -ContentType "application/json" -UseBasicParsing | ConvertFrom-Json).hits.hits
if ($sample.Count -gt 0) {
    $src = $sample[0]._source
    $fields = @("Body","traceId","@timestamp")
    foreach ($f in $fields) {
        $val = $src.$f
        $label = if ($val) { $OK } else { $FAIL }
        $short = if ($val -and $val.ToString().Length -gt 50) { $val.ToString().Substring(0,50) } else { $val }
        Write-Host "  $label campo '$f' = $short"
    }
    $svcName = if ($src.service) { $src.service.name } else { $null }
    $lvl = if ($src.log) { $src.log.level } else { $null }
    Write-Host "  $OK campo 'service.name' = $svcName"
    Write-Host "  $OK campo 'log.level' = $lvl"
}

# ===================== 6. JAEGER =====================
Write-Host ""
Write-Host "--- 6. JAEGER ---"
$svcs = (Invoke-WebRequest "http://localhost:16686/api/services" -UseBasicParsing | ConvertFrom-Json).data
$realSvcs = $svcs | Where-Object { $_ -ne "jaeger-all-in-one" }
Write-Host "  $OK Servicios instrumentados: $($realSvcs -join ', ')"
foreach ($svc in $realSvcs) {
    $ops = (Invoke-WebRequest "http://localhost:16686/api/operations?service=$([uri]::EscapeDataString($svc))" -UseBasicParsing | ConvertFrom-Json).data
    Write-Host "  $OK $svc -> $($ops.Count) operaciones"
    foreach ($op in $ops) { Write-Host "    - $($op.name) ($($op.spanKind))" }
}

# ===================== 7. GRAFANA =====================
Write-Host ""
Write-Host "--- 7. GRAFANA ---"
$headers = @{ Authorization = "Basic YWRtaW46YWRtaW4=" }
$dbs = (Invoke-WebRequest "http://localhost:3000/api/search?type=dash-db" -Headers $headers -UseBasicParsing | ConvertFrom-Json)
Write-Host "  $OK Dashboards: $($dbs.Count)"
foreach ($d in $dbs) { Write-Host "    - $($d.title) [uid=$($d.uid)]" }

$alertRules = (Invoke-WebRequest "http://localhost:3000/api/v1/provisioning/alert-rules" -Headers $headers -UseBasicParsing | ConvertFrom-Json)
Write-Host "  $OK Alertas: $($alertRules.Count)"
foreach ($a in $alertRules) { Write-Host "    - [$($a.uid)] $($a.title) for=$($a.for)" }

$ds = (Invoke-WebRequest "http://localhost:3000/api/datasources" -Headers $headers -UseBasicParsing | ConvertFrom-Json)
foreach ($d in $ds) { Write-Host "  $OK Datasource: $($d.name) uid=$($d.uid) type=$($d.type)" }

Write-Host ""
Write-Host "======================================================="
Write-Host " FIN VERIFICACION FINAL"
Write-Host "======================================================="
