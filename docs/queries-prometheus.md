# Queries PromQL para Prometheus

## Documentación de queries funcionales para métricas en Prometheus

Prometheus scrapea las métricas del OpenTelemetry Collector en `otel-collector:8889`.
Acceso: **http://localhost:9090** → pestaña "Graph".

> **VALIDADO**: Todas las métricas y labels de esta documentación se verificaron contra
> el endpoint real de Prometheus con los microservicios corriendo con Java Agent 2.27.0.

### Métricas disponibles (verificadas)

| Categoría | Métrica | Descripción |
|-----------|---------|-------------|
| HTTP | `otel_http_server_request_duration_seconds_count` | Conteo de requests HTTP |
| HTTP | `otel_http_server_request_duration_seconds_sum` | Suma duración HTTP |
| HTTP | `otel_http_server_request_duration_seconds_bucket` | Histogram HTTP (para percentiles) |
| HTTP Client | `otel_http_client_request_duration_seconds_*` | Llamadas HTTP salientes |
| JVM CPU | `otel_jvm_cpu_recent_utilization_ratio` | Uso de CPU (0.0-1.0) |
| JVM CPU | `otel_jvm_cpu_time_seconds_total` | Tiempo CPU acumulado |
| JVM CPU | `otel_jvm_cpu_count` | Número de CPUs disponibles |
| JVM Memoria | `otel_jvm_memory_used_bytes` | Memoria usada |
| JVM Memoria | `otel_jvm_memory_committed_bytes` | Memoria comprometida |
| JVM Memoria | `otel_jvm_memory_limit_bytes` | Límite de memoria |
| JVM GC | `otel_jvm_gc_duration_seconds_*` | Duración de Garbage Collection |
| JVM Threads | `otel_jvm_thread_count` | Número de threads |
| JVM Classes | `otel_jvm_class_count` | Clases cargadas |
| DB | `otel_db_client_connections_usage` | Conexiones DB activas |
| DB | `otel_db_client_connections_max` | Máximo de conexiones |

### Labels importantes (Java Agent 2.x — VERIFICADOS)

> **IMPORTANTE**: El label es `exported_job`, NO `service_name`.
> Prometheus renombra `job` a `exported_job` al hacer scraping del Collector.

| Label | Descripción | Valores reales |
|-------|-------------|----------------|
| `exported_job` | Nombre del microservicio | `fx-catalog-service`, `fx-course-service` |
| `http_route` | Ruta del endpoint HTTP | `/catalog`, `/courses`, `/{repository}/{id}` |
| `http_request_method` | Método HTTP | `GET`, `POST`, `DELETE` |
| `http_response_status_code` | Código de respuesta | `200`, `404`, `500` |
| `jvm_memory_type` | Tipo de memoria JVM | `heap`, `non_heap` |
| `jvm_gc_name` | Nombre del GC | `G1 Young Generation` |

---

## 1. Tiempo promedio de respuesta por endpoint

**Qué muestra:** Latencia promedio en milisegundos para cada endpoint HTTP en una ventana de 5 minutos.
**Cuándo usarlo:** Para identificar qué endpoints son más lentos. Normal: <100ms. Preocupante: >500ms sostenido.
**Cómo leerlo:** Cada serie es un endpoint (`/courses`, `/catalog`, `/{id}`). Si una línea sube → ese endpoint está tardando más.

```promql
(
  rate(otel_http_server_request_duration_seconds_sum[5m])
  /
  rate(otel_http_server_request_duration_seconds_count[5m])
) * 1000
```

---

## 2. Solicitudes por minuto por endpoint

**Qué muestra:** Cantidad de requests por minuto agrupados por ruta HTTP.
**Cuándo usarlo:** Para ver el volumen de tráfico por endpoint. Útil para detectar qué endpoint recibe más carga.
**Cómo leerlo:** Picos = ráfagas de tráfico. Valor 0 = ese endpoint no ha recibido requests en el último minuto.

```promql
sum(rate(otel_http_server_request_duration_seconds_count[1m])) by (http_route) * 60
```

---

## 3. Requests por segundo por servicio

**Qué muestra:** Throughput en req/s de cada microservicio (`fx-course-service`, `fx-catalog-service`).
**Cuándo usarlo:** Para comparar la carga entre servicios. Si catalog tiene más carga que course puede indicar llamadas en cascada.
**Cómo leerlo:** `fx-catalog-service` siempre generará ligeramente menos que `fx-course-service` porque catalog llama a course internamente.

```promql
sum(rate(otel_http_server_request_duration_seconds_count[1m])) by (exported_job)
```

---

## 4. Total de solicitudes en la última hora por servicio

**Qué muestra:** Número absoluto de requests procesados en la última hora por cada servicio.
**Cuándo usarlo:** Para dimensionar carga total. Si ejecutas el script de tráfico varias veces, este número debe crecer.
**Cómo leerlo:** Número entero acumulado — no es una tasa, es un total. Útil en vistas de tabla (no gráfico).

```promql
sum(increase(otel_http_server_request_duration_seconds_count{exported_job="fx-catalog-service"}[1h]))
```

```promql
sum(increase(otel_http_server_request_duration_seconds_count{exported_job="fx-course-service"}[1h]))
```

---

## 5. Tasa de errores HTTP 5xx (%)

**Qué muestra:** Porcentaje de requests que retornaron error de servidor (500, 502, 503, etc.) sobre el total.
**Cuándo usarlo:** Para detectar errores internos de la aplicación. Un valor >0 sostenido indica un bug o sobrecarga.
**Cómo leerlo:** 0% = sin errores de servidor. Cualquier valor >5% durante >2 min dispara la alerta `fx-high-error-rate`.

```promql
(
  sum(rate(otel_http_server_request_duration_seconds_count{http_response_status_code=~"5.."}[5m]))
  /
  sum(rate(otel_http_server_request_duration_seconds_count[5m]))
) * 100
```

---

## 6. Tasa de errores HTTP 4xx + 5xx combinados (%)

**Qué muestra:** Porcentaje de requests con cualquier error (cliente o servidor) sobre el total.
**Cuándo usarlo:** Vista combinada de errores. Los 404s del endpoint `/courses/999` del script de tráfico son visibles aquí.
**Cómo leerlo:** Durante el script `generate-traffic-heavy.ps1`, este valor subirá ~10% porque 1 de cada 9 requests es un 404 intencional.

```promql
(
  sum(rate(otel_http_server_request_duration_seconds_count{http_response_status_code=~"[45].."}[5m]))
  /
  sum(rate(otel_http_server_request_duration_seconds_count[5m]))
) * 100
```

---

## 7. Latencia P95 (percentil 95) por servicio

**Qué muestra:** El tiempo de respuesta que el 95% de los requests cumple o supera — los 5% más lentos quedan por encima de este valor.
**Cuándo usarlo:** Mejor indicador de latencia real que el promedio. El promedio puede ocultar picos lentos; P95 no.
**Cómo leerlo:** Si P95=200ms significa que 95 de cada 100 requests respondieron en <200ms. Valor verificado en producción: ~47ms.

```promql
histogram_quantile(0.95,
  sum(rate(otel_http_server_request_duration_seconds_bucket[5m])) by (le, exported_job)
)
```

---

## 8. Latencia P99 por endpoint

**Qué muestra:** El tiempo de respuesta del 1% más lento, por endpoint individual.
**Cuándo usarlo:** Para detectar tail latency — requests específicos que son muy lentos aunque el promedio sea bajo. Si P99 >> P95, hay variabilidad alta.
**Cómo leerlo:** Compara `/courses` vs `/catalog`: catalog será más lento porque hace una llamada HTTP interna a course-service.

```promql
histogram_quantile(0.99,
  sum(rate(otel_http_server_request_duration_seconds_bucket[5m])) by (le, http_route)
)
```

---

## 9. Uso de CPU por servicio (%)

**Qué muestra:** Porcentaje de CPU consumido por la JVM de cada microservicio.
**Cuándo usarlo:** Para detectar sobrecarga. En reposo: 1–5%. Con tráfico intenso: 10–30%. >80% sostenido → alerta `fx-high-cpu`.
**Cómo leerlo:** `fx-course-service` usará más CPU que catalog porque hace queries a MySQL.

```promql
otel_jvm_cpu_recent_utilization_ratio{exported_job="fx-catalog-service"} * 100
```

```promql
otel_jvm_cpu_recent_utilization_ratio{exported_job="fx-course-service"} * 100
```

```promql
otel_jvm_cpu_recent_utilization_ratio * 100
```

---

## 10. Uso de memoria heap por servicio

**Qué muestra:** Bytes de heap JVM actualmente usados por cada servicio (Eden Space + Old Gen).
**Cuándo usarlo:** Para detectar memory leaks (heap que crece indefinidamente) o presión de GC.
**Cómo leerlo:** El heap sube con carga y baja cuando el GC actúa (dientes de sierra = normal). Si solo sube sin bajar → posible leak.

```promql
sum(otel_jvm_memory_used_bytes{jvm_memory_type="heap"}) by (exported_job)
```

---

## 11. Porcentaje de uso de heap (usado / committed)

**Qué muestra:** Qué % del heap asignado (committed) está realmente en uso.
**Cuándo usarlo:** Más útil que los bytes absolutos. >85% → alerta `fx-heap-pressure`. >95% → riesgo de OutOfMemoryError.
**Cómo leerlo:** Valor verificado en operación normal: ~40–60%. El GC debería mantenerlo bajo 85%.

```promql
(
  sum(otel_jvm_memory_used_bytes{jvm_memory_type="heap"}) by (exported_job)
  /
  sum(otel_jvm_memory_committed_bytes{jvm_memory_type="heap"}) by (exported_job)
) * 100
```

---

## 12. Threads activos por servicio

**Qué muestra:** Número de threads activos en la JVM de cada servicio.
**Cuándo usarlo:** Para detectar thread leaks. Normal en Spring Boot: 20–60 threads. Crecimiento sostenido sin techo = problema.
**Cómo leerlo:** Spring Boot usa un thread pool de Tomcat (default 200 max). Si se acerca a 200 → saturación de requests entrantes.

```promql
otel_jvm_thread_count
```

---

## 13. Throughput total del sistema (req/s)

**Qué muestra:** Requests por segundo de todo el sistema (ambos servicios combinados).
**Cuándo usarlo:** Vista global de carga. Útil para correlacionar con CPU/heap: si throughput sube y CPU no → el sistema escala bien.
**Cómo leerlo:** Con `generate-traffic-heavy.ps1`: ~0.6 req/s. En producción real: valor de referencia para detectar caídas de tráfico.

```promql
sum(rate(otel_http_server_request_duration_seconds_count[1m]))
```

---

## 14. Latencia de llamadas HTTP salientes (catalog → course)

**Qué muestra:** Latencia promedio de las llamadas HTTP que `fx-catalog-service` hace a `fx-course-service` (llamadas cliente).
**Cuándo usarlo:** Para aislar si la latencia de `/catalog` viene de la llamada interna a course-service o de su propia lógica.
**Cómo leerlo:** Si esta latencia es alta y la del servidor de course-service también → el problema está en course. Si solo la del cliente es alta → problema de red interna Docker.

```promql
rate(otel_http_client_request_duration_seconds_sum[5m])
/
rate(otel_http_client_request_duration_seconds_count[5m])
```

---

## 15. Conexiones activas a base de datos

**Qué muestra:** Estado del pool de conexiones HikariCP de `fx-course-service` a MySQL.
**Cuándo usarlo:** Para detectar saturación de BD. Si `used` == `max` → las queries están esperando conexión → latencia aumenta.
**Cómo leerlo:** `state="idle"` = conexiones libres (normal: 10). `state="used"` = conexiones activas. `max` = límite del pool (default HikariCP: 10). Valor verificado: idle=10 en reposo.

```promql
otel_db_client_connections_usage
```

```promql
otel_db_client_connections_max
```

---

## 16. Métricas internas del OTel Collector (VERIFICADAS)

**Qué muestra:** Estadísticas internas del OTel Collector: spans procesados, logs procesados, tamaño de cola, y exportaciones realizadas.
**Cuándo usarlo:** Para diagnosticar si el Collector está procesando y exportando correctamente. Si `exported_total` no crece → hay problema de exportación.
**Cómo leerlo:** `otel_queueSize_ratio` cercano a 1.0 indica que la cola está casi llena — puede generar `FRAME_SIZE_ERROR`. Con la config actual (batch 256/512) debe mantenerse bajo.

```promql
otel_processedSpans_total
```

```promql
otel_processedLogs_total
```

```promql
otel_queueSize_ratio
```

```promql
otel_otlp_exporter_exported_total
```

---

## 17. Tasa de error HTTP por endpoint (detallado)

**Qué muestra:** Requests con error (4xx o 5xx) desglosados por endpoint Y servicio simultáneamente.
**Cuándo usarlo:** Para identificar exactamente qué endpoint de qué servicio está fallando. Más específico que el query 6.
**Cómo leerlo:** Busca series donde `http_route="/{id}"` y `exported_job="fx-course-service"` — esas son los 404s de `/courses/999`.

```promql
sum(rate(otel_http_server_request_duration_seconds_count{
  http_response_status_code=~"[45].."
}[5m])) by (http_route, exported_job)
```

---

## 18. Comparar requests de catálogo vs cursos

**Qué muestra:** Req/min de cada servicio por separado para comparación directa.
**Cuándo usarlo:** Para detectar si un servicio recibe desproporcionalmente más carga. Si catalog y course tienen la misma carga → cada request de catalog genera exactamente un request interno a course (llamada 1:1).
**Cómo leerlo:** Con tráfico del script: ambos deberían tener valores similares. Si course tiene el doble → hay llamadas duplicadas.

```promql
sum(rate(otel_http_server_request_duration_seconds_count{
  exported_job="fx-catalog-service"
}[1m])) * 60
```

```promql
sum(rate(otel_http_server_request_duration_seconds_count{
  exported_job="fx-course-service"
}[1m])) * 60
```

---

## Cómo ejecutar estos queries

### Desde Prometheus UI
1. Acceder a http://localhost:9090
2. Ir a la pestaña "Graph"
3. Pegar el query PromQL
4. Click en "Execute"
5. Cambiar entre "Table" y "Graph" para ver diferentes visualizaciones

### Desde cURL (API REST)
```bash
# Query instantáneo
curl "http://localhost:9090/api/v1/query?query=sum(rate(otel_http_server_request_duration_seconds_count[1m]))"

# Query con rango de tiempo
curl "http://localhost:9090/api/v1/query_range?query=sum(rate(otel_http_server_request_duration_seconds_count[1m]))&start=2024-01-01T00:00:00Z&end=2024-01-01T01:00:00Z&step=60s"

# Listar todas las métricas disponibles
curl "http://localhost:9090/api/v1/label/__name__/values" | jq '.data[] | select(startswith("otel_"))'
```

---

## Verificación rápida

Para comprobar que las métricas están llegando correctamente:

```bash
# Ver métricas del endpoint de scrape del collector
curl http://localhost:8889/metrics | grep otel_http_server

# Ver targets activos en Prometheus
curl http://localhost:9090/api/v1/targets
```

---

## Notas importantes

- **Prefijo `otel_`**: Todas las métricas del collector tienen este prefijo (configurado en `otel-collector-config.yaml`)
- **Java Agent**: Genera automáticamente `http.server.request.duration`, `jvm.memory.used`, `jvm.cpu.recent_utilization`, etc.
- **Histogramas**: Generan automáticamente sufijos `_bucket`, `_sum` y `_count`
- **Latencia**: Los histogramas del agent usan segundos; las métricas custom usan milisegundos
- **Labels**: El Java Agent 2.x usa nombres semánticos como `http_response_status_code` (no `http_status_code`)
- **Tiempo de propagación**: Las métricas tardan ~15-30 segundos en aparecer tras el primer request
