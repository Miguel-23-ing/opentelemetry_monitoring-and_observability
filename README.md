# Guía de Observabilidad — FutureX Microservices

> **Documento:** Guía Técnica de Observabilidad con OpenTelemetry  
> **Versión:** 1.0  
> **Stack:** Java 17 · Spring Boot 3.3.3 · OpenTelemetry · Prometheus · Grafana · Jaeger · ELK  
> **Servicios:** `fx-course-service` (8001) · `fx-catalog-service` (8002)

---

## Tabla de Contenidos

1. [Arquitectura](#1-arquitectura)
2. [Stack Tecnológico](#2-stack-tecnológico)
3. [Inicio Rápido](#3-inicio-rápido)
4. [URLs de Acceso](#4-urls-de-acceso)
5. [Jaeger — Trazas Distribuidas](#5-jaeger--trazas-distribuidas)
6. [Prometheus — Métricas](#6-prometheus--métricas)
7. [Grafana — Dashboards](#7-grafana--dashboards)
8. [Kibana — Logs](#8-kibana--logs)
9. [Endpoints de los Microservicios](#9-endpoints-de-los-microservicios)
10. [OpenTelemetry Collector](#10-opentelemetry-collector)
11. [Instrumentación del Código](#11-instrumentación-del-código)
12. [Alertas](#12-alertas)
13. [Queries Documentados](#13-queries-documentados)
14. [Estructura del Proyecto](#14-estructura-del-proyecto)
15. [Solución de Problemas](#15-solución-de-problemas)
16. [Guía de Validación Completa](#16-guía-de-validación-completa)

---

## 1. Arquitectura

```
┌─────────────────┐     ┌─────────────────┐
│  fx-catalog     │────▶│  fx-course      │
│  service:8002   │     │  service:8001   │──▶ MySQL:3306
└────────┬────────┘     └────────┬────────┘
         │ OTLP (métricas,       │ OTLP (métricas,
         │ trazas, logs)         │ trazas, logs)
         ▼                       ▼
┌─────────────────────────────────────────┐
│     OpenTelemetry Collector             │
│     Puerto host: 4320 (HTTP OTLP)      │
│     Puerto host: 4319 (gRPC OTLP)      │
│     Puerto host: 8889 (Prometheus exp.) │
└──────┬──────────┬──────────────┬────────┘
       │          │              │
       ▼          ▼              ▼
┌──────────┐ ┌──────────┐ ┌────────────┐
│  Jaeger  │ │Prometheus│ │ Archivo    │
│  :16686  │ │  :9090   │ │ (logs.json)│
│ (Trazas) │ │(Métricas)│ └─────┬──────┘
└──────────┘ └────┬─────┘       │
                  │              ▼
                  │    ┌───────────────┐
                  │    │   Logstash    │
                  │    │  (pipeline)   │
                  │    └───────┬───────┘
                  │            │
                  ▼            ▼
           ┌──────────┐ ┌───────────────┐
           │ Grafana  │ │Elasticsearch  │
           │  :3000   │ │   :9200       │
           │(Dashboards│ └───────┬───────┘
           └──────────┘         │
                                ▼
                         ┌───────────────┐
                         │    Kibana     │
                         │    :5601      │
                         │   (Logs UI)   │
                         └───────────────┘
```

### Flujo de datos

1. Los microservicios envían telemetría (trazas, métricas, logs) al **OTel Collector** via OTLP HTTP (puerto 4320).
2. El Collector procesa y distribuye:
   - **Trazas** → Jaeger (almacena y visualiza trazas distribuidas)
   - **Métricas** → Prometheus (scrapea el endpoint `/metrics` del Collector en :8889)
   - **Logs** → Archivo JSON → Logstash lee el archivo → Elasticsearch indexa → Kibana visualiza
3. **Grafana** conecta a Prometheus, Elasticsearch y Jaeger como datasources para dashboards unificados.

---

## 2. Stack Tecnológico

| Componente | Tecnología | Versión |
|-----------|-----------|---------|
| Lenguaje | Java | 17+ |
| Framework | Spring Boot | 3.3.3 |
| Base de datos | MySQL | 8.0 |
| Instrumentación | OpenTelemetry Java Agent | 2.27.0 |
| Collector | OpenTelemetry Collector Contrib | 0.88.0 |
| Trazas | Jaeger (all-in-one) | latest |
| Métricas | Prometheus | v2.47.0 |
| Dashboards | Grafana | 10.1.0 |
| Búsqueda de logs | Elasticsearch | 7.17.0 |
| Pipeline de logs | Logstash | 7.17.0 |
| UI de logs | Kibana | 7.17.0 |
| Build | Maven | wrapper incluido |

---

## 3. Inicio Rápido

### Paso 1: Levantar toda la infraestructura

```bash
docker compose up -d
```

Esto levanta **8 contenedores**: Jaeger, OTel Collector, Prometheus, Grafana, Elasticsearch, Logstash, Kibana y MySQL.

Verificar que todos estén corriendo:
```bash
docker compose ps
```

Esperar a que todos reporten `healthy`:
```bash
# Debe mostrar: jaeger(healthy), prometheus(healthy), elasticsearch(healthy),
# kibana(healthy), mysql(healthy), grafana(Up), logstash(Up), otel-collector(Up)
```

### Paso 2: Compilar los microservicios

```bash
# Compilar fx-course-service
cd parte0-JaegerCourseApp
./mvnw clean package -DskipTests
cd ..

# Compilar fx-catalog-service
cd part0-JaegerCourseCatalog
./mvnw clean package -DskipTests
cd ..
```

> **Windows:** Usar `.\mvnw.cmd` en lugar de `./mvnw`

### Paso 3: Ejecutar con el Java Agent

> **IMPORTANTE:** Usar puerto **4320** (HTTP OTLP). El puerto 4319 es gRPC y el agent usa HTTP por defecto.

**fx-course-service (puerto 8001):**
```bash
java -javaagent:opentelemetry-javaagent.jar \
     -Dotel.service.name=fx-course-service \
     -Dotel.exporter.otlp.endpoint=http://localhost:4320 \
     -Dotel.metrics.exporter=otlp \
     -Dotel.logs.exporter=otlp \
     -Dotel.traces.exporter=otlp \
     -jar parte0-JaegerCourseApp/target/FutureXCourseApp-0.0.1-SNAPSHOT.jar
```

**fx-catalog-service (puerto 8002):**
```bash
java -javaagent:opentelemetry-javaagent.jar \
     -Dotel.service.name=fx-catalog-service \
     -Dotel.exporter.otlp.endpoint=http://localhost:4320 \
     -Dotel.metrics.exporter=otlp \
     -Dotel.logs.exporter=otlp \
     -Dotel.traces.exporter=otlp \
     -jar part0-JaegerCourseCatalog/target/FutureXCourseCatalog-0.0.1-SNAPSHOT.jar
```

> **Windows (PowerShell):** Envolver cada `-D` en comillas: `"-Dotel.service.name=fx-course-service"`

### Paso 4: Generar tráfico

```bash
# Listar todos los cursos
curl http://localhost:8001/courses

# Obtener un curso por ID
curl http://localhost:8001/courses/1

# Catálogo (llama internamente a fx-course-service → traza distribuida)
curl http://localhost:8002/catalog

# Generar un 404 para ver errores
curl http://localhost:8001/courses/999
```

O ejecutar el script incluido:
```bash
# PowerShell
powershell -ExecutionPolicy Bypass -File generate-traffic.ps1
```

### Paso 5: Verificar telemetría

Ejecutar el script de verificación:
```bash
powershell -ExecutionPolicy Bypass -File verify.ps1
```

---

## 4. URLs de Acceso

### ⚡ Referencia rápida

> Generar tráfico de prueba (ejecutar antes de explorar los dashboards):
> ```powershell
> powershell -ExecutionPolicy Bypass -File generate-traffic-heavy.ps1
> ```

**Herramientas de Observabilidad**

- Jaeger → http://localhost:16686
- Prometheus → http://localhost:9090
- Grafana → http://localhost:3000 *(admin / admin)*
- Kibana → http://localhost:5601
- Elasticsearch → http://localhost:9200

**Grafana — Dashboards**

- Observabilidad General → http://localhost:3000/d/futurex-observability
- Requests por Endpoint → http://localhost:3000/d/futurex-requests-endpoint
- CPU y Memoria → http://localhost:3000/d/futurex-resources
- Errores vs Éxitos → http://localhost:3000/d/futurex-errors-success
- Avanzado / Anomalías → http://localhost:3000/d/futurex-advanced
- Alertas → http://localhost:3000/alerting/list

**Kibana**

- Dashboard principal → http://localhost:5601/app/dashboards#/view/futurex-kibana-logs
- Dev Tools → http://localhost:5601/app/dev_tools#/console
- Discover → http://localhost:5601/app/discover
- Index Patterns → http://localhost:5601/app/management/kibana/indexPatterns

**Prometheus**

- Queries PromQL → http://localhost:9090/graph
- Targets → http://localhost:9090/targets
- Alertas → http://localhost:9090/alerts
- Métricas raw del Collector → http://localhost:8889/metrics

**Microservicios**

- Cursos (lista) → http://localhost:8001/courses
- Curso por ID → http://localhost:8001/courses/1
- 404 intencional → http://localhost:8001/courses/999
- Catálogo (traza distribuida) → http://localhost:8002/catalog
- Primer curso → http://localhost:8002/firstcourse
- Health course-service → http://localhost:8001/actuator/health
- Health catalog-service → http://localhost:8002/actuator/health

**Elasticsearch (diagnóstico)**

- Estado del cluster → http://localhost:9200
- Índices → http://localhost:9200/_cat/indices?v
- Mapping de logs → http://localhost:9200/otel-logs-*/_mapping
- Logstash monitoring → http://localhost:9600

---

### 🔗 Tabla detallada — todos los enlaces

#### Herramientas de Observabilidad

| Herramienta | URL principal | Credenciales | Qué hace |
|-------------|--------------|-------------|----------|
| **Jaeger** | http://localhost:16686 | Sin auth | Trazas distribuidas — spans, waterfall, correlación entre servicios |
| **Prometheus** | http://localhost:9090 | Sin auth | Métricas — queries PromQL, targets activos, alertas |
| **Grafana** | http://localhost:3000 | admin / admin | Dashboards — métricas, alertas, correlación |
| **Kibana** | http://localhost:5601 | Sin auth | Logs — discover, dashboard, saved searches |
| **Elasticsearch** | http://localhost:9200 | Sin auth | API REST de búsqueda de logs (Dev Tools desde Kibana) |

#### Dashboards de Grafana

| Dashboard | URL | Qué muestra |
|-----------|-----|-------------|
| Observabilidad General | http://localhost:3000/d/futurex-observability | Overview: tráfico, latencia, errores, CPU, heap |
| Ejemplo 1: Requests por Endpoint | http://localhost:3000/d/futurex-requests-endpoint | Req/min por endpoint y servicio, método HTTP |
| Ejemplo 2: CPU y Memoria | http://localhost:3000/d/futurex-resources | CPU JVM, heap, threads, GC |
| Ejemplo 3: Errores vs Éxitos | http://localhost:3000/d/futurex-errors-success | Tasa de error %, distribución status codes |
| Avanzado: Anomalías y Correlación | http://localhost:3000/d/futurex-advanced | Anomalías, correlación latencia/errores/CPU, P50/P95/P99 |
| Alertas activas | http://localhost:3000/alerting/list | 5 reglas de alerta configuradas |

#### Dashboards y vistas de Kibana

| Vista | URL | Qué muestra |
|-------|-----|-------------|
| Dashboard principal | http://localhost:5601/app/dashboards#/view/futurex-kibana-logs | 6 paneles: volumen, errores, pie, bar, metric, tabla |
| Discover — Logs con TraceId | http://localhost:5601/app/discover#/?_a=(savedQuery:'futurex-search-traced-logs') | Logs con traceId, columnas preconfiguradas |
| Dev Tools | http://localhost:5601/app/dev_tools#/console | Queries JSON contra Elasticsearch |
| Index Pattern | http://localhost:5601/app/management/kibana/indexPatterns | Ver el index pattern `otel-logs-*` |

#### Vistas de Prometheus

| Vista | URL | Qué muestra |
|-------|-----|-------------|
| Graph (queries PromQL) | http://localhost:9090/graph | Ejecutar cualquier query PromQL |
| Targets activos | http://localhost:9090/targets | Estado del scrape a `otel-collector:8889` |
| Alertas activas | http://localhost:9090/alerts | Estado de las alertas definidas en `prometheus_alert_rules.yml` |
| Métricas raw del Collector | http://localhost:8889/metrics | Endpoint de scrape — todas las métricas en formato Prometheus |

#### Endpoints de los Microservicios

| Servicio | Método | URL | Descripción |
|----------|--------|-----|-------------|
| fx-course-service | GET | http://localhost:8001/courses | Lista todos los cursos (con query MySQL) |
| fx-course-service | GET | http://localhost:8001/courses/1 | Obtiene curso por ID |
| fx-course-service | GET | http://localhost:8001/courses/999 | Genera 404 intencional (prueba de errores) |
| fx-course-service | POST | http://localhost:8001/courses | Crear nuevo curso |
| fx-course-service | GET | http://localhost:8001/actuator/health | Health check |
| fx-catalog-service | GET | http://localhost:8002/catalog | Catálogo completo (llama internamente a course-service → traza distribuida) |
| fx-catalog-service | GET | http://localhost:8002/firstcourse | Primer curso del catálogo |
| fx-catalog-service | GET | http://localhost:8002/actuator/health | Health check |

#### Infraestructura interna (diagnóstico)

| Servicio | URL | Qué muestra |
|----------|-----|-------------|
| Elasticsearch API | http://localhost:9200 | Estado del cluster, índices |
| Elasticsearch índices | http://localhost:9200/_cat/indices?v | Lista de índices incluyendo `otel-logs-*` |
| Elasticsearch mapping | http://localhost:9200/otel-logs-*/_mapping | Campos disponibles en el índice de logs |
| Logstash monitoring | http://localhost:9600 | Estado del pipeline de Logstash |

---

## 5. Jaeger — Trazas Distribuidas

**URL:** http://localhost:16686

### Qué ver en Jaeger

1. **Abrir** http://localhost:16686
2. En el dropdown **"Service"**, seleccionar `fx-course-service` o `fx-catalog-service`
3. Click en **"Find Traces"**
4. Se muestra una lista de trazas con duración y número de spans
5. Click en una traza para ver el **diagrama de cascada (waterfall)**:
   - Cada barra horizontal es un **span** (una operación)
   - Las trazas del catálogo muestran spans en **ambos servicios** (traza distribuida)
   - Cada span tiene atributos: `http.method`, `http.route`, `http.response_status_code`

### Servicios visibles en Jaeger

| Servicio | Descripción |
|----------|-------------|
| `fx-course-service` | Spans de endpoints CRUD de cursos |
| `fx-catalog-service` | Spans del catálogo + llamadas HTTP salientes al servicio de cursos |
| `jaeger-all-in-one` | Spans internos de Jaeger |

### Cómo usar el traceId para correlación

1. En Jaeger, click en una traza → copiar el **Trace ID** (ej: `abc123def456...`)
2. Usar ese ID en **Kibana** para buscar los logs de esa traza:
   ```
   traceId: "abc123def456..."
   ```
3. Usar ese ID en **Grafana** (datasource Jaeger) para ver la traza desde el dashboard

---

## 6. Prometheus — Métricas

**URL:** http://localhost:9090

### Qué ver en Prometheus

1. **Abrir** http://localhost:9090
2. Ir a la pestaña **"Graph"**
3. Pegar un query PromQL en el campo de texto
4. Click en **"Execute"**
5. Cambiar entre **"Table"** (valores puntuales) y **"Graph"** (serie temporal)

### Queries rápidos para probar

```promql
# Ver todas las métricas HTTP del Java Agent
otel_http_server_request_duration_seconds_count

# Solicitudes por minuto por endpoint
sum(rate(otel_http_server_request_duration_seconds_count[1m])) by (http_route) * 60

# Uso de CPU por servicio (%)
otel_jvm_cpu_recent_utilization_ratio * 100

# Memoria heap usada
sum(otel_jvm_memory_used_bytes{jvm_memory_type="heap"}) by (service_name)

# Tasa de errores 5xx (%)
sum(rate(otel_http_server_request_duration_seconds_count{http_response_status_code=~"5.."}[5m]))
/
sum(rate(otel_http_server_request_duration_seconds_count[5m])) * 100
```

### Ver targets de scraping

Abrir http://localhost:9090/targets para verificar que Prometheus está scrapeando el OTel Collector:
- **otel-collector** → `http://otel-collector:8889/metrics` → State: **UP**

### Ver alertas activas

Abrir http://localhost:9090/alerts para ver el estado de las 5 reglas de alerta configuradas.

### Convención de nombres de métricas

| Fuente | Prefijo | Ejemplo |
|--------|---------|---------|
| Java Agent (auto) | `otel_http_server_*`, `otel_jvm_*` | `otel_http_server_request_duration_seconds_count` |
| Métricas custom | `otel_fx_catalog_*`, `otel_fx_course_*` | `otel_fx_catalog_requests_total` |
| Collector interno | `otel_exporter_*`, `otel_receiver_*` | `otel_receiver_accepted_spans_total` |

### Labels importantes

| Label | Descripción | Ejemplo |
|-------|-------------|---------|
| `service_name` | Nombre del microservicio | `fx-catalog-service` |
| `http_route` | Ruta/endpoint HTTP | `/catalog`, `/courses` |
| `http_request_method` | Método HTTP | `GET`, `POST`, `DELETE` |
| `http_response_status_code` | Código de respuesta | `200`, `404`, `500` |

> **Nota:** El Java Agent 2.x usa `http_response_status_code` (NO `http_status_code`)

---

## 7. Grafana — Dashboards

**URL:** http://localhost:3000  
**Login:** admin / admin (saltar cambio de contraseña)

### Cómo acceder a los dashboards

1. **Abrir** http://localhost:3000
2. Login con **admin** / **admin**
3. En el menú lateral izquierdo → **Dashboards** → carpeta **"FutureX"**
4. Se listan los 4 dashboards

### Dashboard 1: Observabilidad General

**URL directa:** http://localhost:3000/d/futurex-observability

| Panel | Tipo | Qué muestra |
|-------|------|-------------|
| Solicitudes/min por Endpoint | Timeseries | Tráfico HTTP agrupado por ruta |
| Latencia Promedio (ms) | Timeseries | Tiempo de respuesta por endpoint |
| Errores vs Éxitos | Pie chart (donut) | Distribución 2xx vs 4xx vs 5xx |
| Total Solicitudes (1h) | Stat | Contadores por servicio |
| Latencia P95 | Gauge | Percentil 95 por servicio |
| CPU por Servicio | Timeseries | Uso de CPU JVM |
| Memoria Heap | Timeseries | Memoria JVM usada |
| Logs Recientes | Logs panel | Últimos logs de Elasticsearch |

### Dashboard 2: Solicitudes por Endpoint

**URL directa:** http://localhost:3000/d/futurex-requests-endpoint

| Panel | Tipo | Qué muestra |
|-------|------|-------------|
| Solicitudes/min (Java Agent) | Timeseries | Todas las rutas HTTP auto-instrumentadas |
| Solicitudes/min (Catálogo custom) | Timeseries | Métricas `fx_catalog_requests_total` |
| Solicitudes/min (Cursos custom) | Timeseries | Métricas `fx_course_requests_total` |
| Total por Servicio | Stat | Contadores en la última hora |
| Solicitudes por Método HTTP | Pie chart | GET vs POST vs DELETE |

### Dashboard 3: CPU y Memoria

**URL directa:** http://localhost:3000/d/futurex-resources

| Panel | Tipo | Qué muestra |
|-------|------|-------------|
| CPU por Servicio | Timeseries | Uso de CPU (%) por JVM |
| Memoria Heap | Timeseries | Heap used vs committed |
| Threads JVM | Timeseries | Número de threads activos |
| CPU Actual | Gauge | Uso actual de CPU por servicio |
| Memoria Heap Actual | Gauge | % de heap usado |
| Garbage Collection | Timeseries | Duración de GC por servicio |

### Dashboard 4: Errores vs Éxitos

**URL directa:** http://localhost:3000/d/futurex-errors-success  
**Rango de tiempo por defecto:** Últimas 6 horas

| Panel | Tipo | Qué muestra |
|-------|------|-------------|
| Distribución (6h) | Pie chart (donut) | 2xx (verde) vs 3xx (azul) vs 4xx (naranja) vs 5xx (rojo) |
| Tasa de Error (%) | Timeseries | % de errores en el tiempo |
| Errores vs Éxitos por Servicio | Timeseries | Separado por fx-catalog y fx-course |
| Correlación Error-Latencia | Timeseries (dual axis) | Tasa de error vs latencia P95 |
| Status Codes por Endpoint | Tabla | Conteo por ruta, status y servicio |

### Datasources configurados

| Datasource | Tipo | URL interna | Uso |
|-----------|------|-------------|-----|
| Prometheus | Default | http://prometheus:9090 | Métricas en dashboards |
| Elasticsearch | Logs | http://elasticsearch:9200 | Panel de logs recientes |
| Jaeger | Trazas | http://jaeger:16686 | Exploración de trazas |

---

## 8. Kibana — Logs

**URL:** http://localhost:5601

> El index pattern, las visualizaciones, los saved searches y el dashboard están **preconfigurados** — no requieren configuración manual.

### Dashboard principal

**→ http://localhost:5601/app/dashboards#/view/futurex-kibana-logs**

Rango de tiempo por defecto: **Last 3 hours**. Contiene 6 paneles:

---

#### Panel 1 — FutureX: Volumen de Logs en el Tiempo *(Line chart)*

**Qué muestra:** Cantidad de logs generados por cada microservicio a lo largo del tiempo, agrupados por intervalos automáticos.

**Cómo leerlo:**
- Eje X → tiempo. Eje Y → cantidad de logs por intervalo.
- Dos líneas: `fx-course-service` y `fx-catalog-service`.
- **Picos** indican momentos de alta actividad (tráfico intenso, errores en ráfaga, reinicio de servicio).
- Línea plana y baja → el servicio está inactivo o con poco tráfico.
- Si una línea desaparece → ese servicio no está enviando logs.

**Campos usados:** `@timestamp`, `service.name.keyword`

---

#### Panel 2 — FutureX: Logs WARNING y ERROR en el Tiempo *(Area chart)*

**Qué muestra:** Solo los logs con nivel `WARNING`, `ERROR` o `WARN`, separados por servicio y apilados en el tiempo.

**Cómo leerlo:**
- El área coloreada representa la densidad de errores/warnings.
- Un pico en una franja específica indica que en ese momento ocurrieron errores (ej: fallos de exportación de métricas, excepciones).
- `fx-course-service` tiende a generar más warnings porque exporta métricas de BD.
- Útil para detectar degradaciones: si el área crece mientras el volumen total no cambia, la proporción de errores aumentó.

**Campos usados:** `@timestamp`, `service.name.keyword`, filtro `log.level.keyword:(WARNING OR ERROR OR WARN)`

---

#### Panel 3 — FutureX: Logs por Servicio *(Pie chart)*

**Qué muestra:** Proporción total de logs generados por cada microservicio en el período seleccionado.

**Cómo leerlo:**
- Una distribución cercana al 50/50 indica que ambos servicios están activos y recibiendo tráfico similar.
- Si un servicio domina (ej: 80%), puede indicar más actividad, más errores, o que el otro servicio está casi inactivo.
- En condiciones normales de tráfico: `fx-course-service` ≈ 51%, `fx-catalog-service` ≈ 49%.

**Campos usados:** `service.name.keyword`

---

#### Panel 4 — FutureX: Logs por Nivel de Severidad *(Bar chart)*

**Qué muestra:** Distribución de todos los logs según su nivel de severidad OTLP.

**Cómo leerlo:**
- **WARNING** (barra más alta) → los más frecuentes; son los warnings internos del OTel Collector sobre exportación de métricas — son normales.
- **INFO** → logs de negocio reales: `"Request received at /courses endpoint - traceId=..."` — estos son los logs de los microservicios.
- **WARN** → variante adicional del nivel warning.
- Si aparece **ERROR** con barra alta → hay un problema real en la aplicación.
- La diferencia entre WARNING e INFO indica la proporción de ruido (interno) vs señal (negocio).

**Campos usados:** `log.level.keyword`

---

#### Panel 5 — FutureX: Logs con TraceId *(Metric)*

**Qué muestra:** Número total de logs que tienen un `traceId` válido y no vacío en el período seleccionado.

**Cómo leerlo:**
- Un número alto (ej: **834**) confirma que los logs de los microservicios están correctamente correlacionados con sus trazas distribuidas.
- Si el valor es 0 → los microservicios no están enviando logs o el traceId no se está propagando.
- Este número debe crecer al generar tráfico con `generate-traffic-heavy.ps1`.
- Para correlacionar: copiar cualquier `traceId` de la tabla inferior y buscarlo en Jaeger.

**Campos usados:** filtro `traceId:* AND NOT traceId:""`

---

#### Panel 6 — FutureX: Logs con TraceId para Correlación *(Tabla / Saved Search)*

**Qué muestra:** Tabla de logs recientes que tienen traceId real, con columnas preconfiguradas.

**Columnas visibles:**

| Columna | Contenido | Ejemplo |
|---------|-----------|---------|
| `Time` | Timestamp legible del log | `May 24, 2026 @ 19:59:55` |
| `@timestamp` | Timestamp ISO del log | `2026-05-25T00:59:55.915Z` |
| `service.name` | Microservicio que generó el log | `fx-course-service` |
| `log.level` | Nivel de severidad | `INFO` |
| `traceId` | ID de la traza distribuida (32 hex) | `c81df297bf4f9ae5c...` |
| `Body` | Mensaje completo del log | `"Request received at /1 endpoint - traceId=c81df297..."` |

**Cómo usar para correlación:**
1. Identificar una fila de `fx-catalog-service` con nivel `INFO`
2. Copiar el valor de `traceId`
3. Abrir **Jaeger** → pegar el traceId → ver la traza distribuida completa con spans de ambos servicios
4. O buscar en Kibana: `traceId: "c81df297bf4f9ae5c0801021cb288cf9"` → verás 2 docs (uno por servicio)

### Saved Searches disponibles

Menú lateral → **Discover** → icono de carpeta → Open:

| Nombre | Filtro aplicado |
|--------|----------------|
| `FutureX - Logs con TraceId para Correlacion` | `traceId:*` (solo logs con traza real) |
| `FutureX - Logs WARNING y ERROR` | `log.level.keyword:(WARNING OR ERROR OR WARN)` |

### Ver todos los logs en Discover

1. Abrir **Discover** → seleccionar index pattern **`otel-logs-*`**
2. Añadir columnas: click `+` junto a `service.name`, `log.level`, `Body`, `traceId`
3. Rango de tiempo: ajustar a "Last 1 hour" o "Last 24 hours"

### Queries KQL verificados

```
# Todos los logs INFO con traceId real (correlación con Jaeger)
log.level: INFO AND traceId: *

# Solo errores/warnings
log.level.keyword: (WARNING OR ERROR)

# Logs de un servicio específico
service.name: "fx-catalog-service"

# Logs del endpoint /catalog
Body: "/catalog"

# Logs de un request específico por traceId (pegar desde Jaeger)
traceId: "PEGAR_TRACE_ID_AQUI"

# Requests del endpoint /courses con traceId
service.name: "fx-course-service" AND Body: "/courses" AND traceId: *

# Correlación distribuida: mismo traceId en ambos servicios
traceId: "PEGAR_TRACE_ID_AQUI"
# → Debe retornar 2 documentos: uno de fx-catalog-service y uno de fx-course-service
```

### Campos disponibles en el índice `otel-logs-*`

| Campo | Tipo ES | Descripción | Ejemplo |
|-------|---------|-------------|---------|
| `@timestamp` | `date` | Timestamp del log | `2026-05-25T00:30:00.000Z` |
| `service.name` | `text` + `.keyword` | Microservicio origen | `fx-catalog-service` |
| `log.level` | `text` + `.keyword` | Nivel de severidad | `INFO`, `WARNING` |
| `Body` | `text` | Mensaje del log | `"Request received at /catalog..."` |
| `traceId` | `text` | ID de traza W3C (correlación Jaeger) | `91424f8427c56bbab1...` |
| `spanId` | `text` | ID del span | `abc123...` |
| `severityNumber` | `long` | Nivel numérico OTLP | 9=INFO, 13=WARNING, 17=ERROR |

### Usar Dev Tools (queries avanzados sobre ES)

Menú lateral → **Dev Tools** → pegar:

```json
GET otel-logs-*/_search
{
  "size": 10,
  "query": {
    "bool": {
      "must": [
        { "match": { "log.level": "INFO" } },
        { "exists": { "field": "traceId" } }
      ],
      "must_not": [ { "term": { "traceId": "" } } ]
    }
  },
  "sort": [{ "@timestamp": { "order": "desc" } }]
}
```

```json
GET otel-logs-*/_count
{
  "query": {
    "term": { "service.name.keyword": "fx-course-service" }
  }
}
```

---

## 9. Endpoints de los Microservicios

### fx-course-service (puerto 8001)

| Método | Endpoint | Descripción |
|--------|----------|-------------|
| GET | `/courses` | Lista todos los cursos |
| GET | `/courses/{id}` | Obtiene un curso por ID |
| POST | `/courses` | Crea un nuevo curso |
| DELETE | `/courses/{id}` | Elimina un curso |
| GET | `/actuator/health` | Health check |
| GET | `/actuator/metrics` | Métricas de Spring Actuator |

### fx-catalog-service (puerto 8002)

| Método | Endpoint | Descripción |
|--------|----------|-------------|
| GET | `/catalog` | Lista el catálogo completo (llama a fx-course-service) |
| GET | `/firstcourse` | Obtiene el primer curso del catálogo |
| GET | `/` | Endpoint raíz |
| GET | `/actuator/health` | Health check |

### Ejemplos con cURL

```bash
# Listar cursos
curl http://localhost:8001/courses

# Crear un curso
curl -X POST http://localhost:8001/courses \
  -H "Content-Type: application/json" \
  -d '{"courseid":4,"coursename":"Microservices","author":"John"}'

# Catálogo (traza distribuida → fx-catalog llama a fx-course)
curl http://localhost:8002/catalog

# Eliminar un curso
curl -X DELETE http://localhost:8001/courses/4
```

---

## 10. OpenTelemetry Collector

### Pipelines configuradas

| Pipeline | Receiver | Processors | Exporters |
|----------|----------|-----------|-----------|
| **Traces** | OTLP (gRPC + HTTP) | memory_limiter, batch | Jaeger (OTLP), logging |
| **Metrics** | OTLP (gRPC + HTTP) | memory_limiter, batch | Prometheus, logging |
| **Logs** | OTLP (gRPC + HTTP) | batch | File (`/var/log/otel-collector.log`), logging |

### Puertos del Collector

| Puerto host | Puerto container | Protocolo | Uso |
|-------------|-----------------|-----------|-----|
| 4320 | 4318 | HTTP OTLP | **Usar este** - Los microservicios envían telemetría aquí |
| 4319 | 4317 | gRPC OTLP | Alternativa si se configura `-Dotel.exporter.otlp.protocol=grpc` |
| 8889 | 8889 | HTTP | Prometheus scrapea métricas de aquí |

> **IMPORTANTE:** El Java Agent v2.x usa HTTP por defecto. Siempre usar puerto **4320**, no 4319.

---

## 11. Instrumentación del Código

### Doble instrumentación: Automática + Manual

1. **Automática (Java Agent):** El archivo `opentelemetry-javaagent.jar` instrumenta automáticamente:
   - Todas las solicitudes HTTP entrantes y salientes
   - JDBC / MySQL queries
   - JVM metrics (CPU, memoria, threads, GC)
   - Context propagation (W3C TraceContext)

2. **Manual (código):** Añadida en los controllers:
   - Métricas personalizadas: `fx_course_requests_total`, `fx_catalog_requests_total`
   - Histogramas de duración: `fx_course_request_duration_ms`, `fx_catalog_request_duration_ms`
   - Spans con atributos custom: `endpoint`, `service.name`, `http.method`
   - Logging estructurado con `traceId`/`spanId`

### OpenTelemetryConfig.java (compatibilidad con Agent)

La clase detecta si el Java Agent ya registró un SDK global:
- **Si el Agent está presente:** Reutiliza el SDK global (evita conflictos)
- **Si no hay Agent:** Crea el SDK manualmente con exporters OTLP

---

## 12. Alertas

### Prometheus Alert Rules

Visibles en: http://localhost:9090/alerts

| Alerta | Condición | Severidad | Duración |
|--------|-----------|-----------|----------|
| `HighErrorRate` | >10% respuestas 5xx en 5 min | warning | 2 min |
| `HighLatency` | P95 latencia > 2 segundos | critical | 3 min |
| `NoTraffic` | Sin solicitudes HTTP en 10 min | info | 10 min |
| `CatalogHighLatency` | Latencia promedio catálogo > 1s | warning | 2 min |
| `CourseHighLatency` | Latencia promedio cursos > 1s | warning | 2 min |

---

## 13. Queries Documentados

### Prometheus (PromQL) — 16 queries

Archivo: [docs/queries-prometheus.md](docs/queries-prometheus.md)

Incluye queries para:
- Latencia promedio por endpoint
- Solicitudes por minuto
- Tasa de errores HTTP
- Percentiles P95 y P99
- Uso de CPU y memoria JVM
- Threads activos
- Métricas personalizadas
- Métricas internas del Collector

### Elasticsearch — 10 queries

Archivo: [docs/queries-elasticsearch.md](docs/queries-elasticsearch.md)

Incluye queries para:
- Logs ERROR/WARN por servicio
- Búsqueda por traceId (correlación con Jaeger)
- Correlación errores-endpoints
- Agregaciones por servicio y nivel
- Full-text search con highlighting

---

## 14. Estructura del Proyecto

```
OpenTelemetry/
├── docker-compose.yml                  # 8 contenedores de infraestructura
├── otel-collector-config.yaml          # Pipelines: traces→Jaeger, metrics→Prometheus, logs→archivo
├── prometheus.yml                      # Scrape config: otel-collector:8889
├── prometheus_alert_rules.yml          # 5 reglas de alerta
├── logstash.conf                       # Lee JSON OTLP → parsea → Elasticsearch
├── opentelemetry-javaagent.jar         # Agent v2.27.0 para instrumentación automática
├── generate-traffic.ps1                # Script para generar tráfico de prueba
├── verify.ps1                          # Script para verificar que todo funciona
├── logs/.gitkeep                       # Volumen compartido OTel Collector → Logstash
│
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/datasources.yml         # Prometheus + Elasticsearch + Jaeger
│   │   └── dashboards/dashboards.yml           # Auto-carga dashboards al iniciar
│   └── dashboards/
│       ├── futurex-observability.json           # Dashboard principal (8 paneles)
│       ├── futurex-requests-per-endpoint.json   # Dashboard 1: Requests (5 paneles)
│       ├── futurex-resources.json               # Dashboard 2: CPU/Mem (6 paneles)
│       └── futurex-errors-vs-success.json       # Dashboard 3: Errores (5 paneles)
│
├── docs/
│   ├── queries-prometheus.md           # 16 queries PromQL documentados
│   └── queries-elasticsearch.md        # 10 queries Elasticsearch documentados
│
├── parte0-JaegerCourseApp/             # fx-course-service (puerto 8001)
│   ├── pom.xml                         # OTel SDK + Actuator + Micrometer
│   └── src/main/
│       ├── java/.../
│       │   ├── CourseController.java           # CRUD + métricas custom + spans + logging
│       │   ├── OpenTelemetryConfig.java        # SDK config (compatible con Agent)
│       │   ├── Course.java                     # Entidad JPA
│       │   ├── CourseRepository.java           # Spring Data repository
│       │   └── DataLoader.java                 # Carga datos iniciales
│       └── resources/
│           ├── application.properties          # Puerto 8001, MySQL, OTLP config
│           └── logback-spring.xml              # Appender OTLP para logs
│
└── part0-JaegerCourseCatalog/          # fx-catalog-service (puerto 8002)
    ├── pom.xml                         # OTel SDK + Actuator + Micrometer
    └── src/main/
        ├── java/.../
        │   ├── CatalogController.java          # Llama a course-service + métricas + spans
        │   ├── OpenTelemetryConfig.java        # SDK config (compatible con Agent)
        │   └── RestTemplateConfig.java         # RestTemplate con OTel interceptor
        └── resources/
            ├── application.properties          # Puerto 8002, OTLP config
            └── logback-spring.xml              # Appender OTLP para logs
```

---

## 15. Solución de Problemas

### El OTel Collector no arranca
```bash
docker logs otel-collector --tail 20
```
- Si dice `permission denied`: El Collector necesita `user: "0:0"` en docker-compose (ya configurado).
- Si dice `failed to build pipelines`: Revisar `otel-collector-config.yaml`.

### No aparecen métricas en Prometheus
1. Verificar target: http://localhost:9090/targets → debe decir **UP**
2. Verificar que el endpoint responde: `curl http://localhost:8889/metrics`
3. Las métricas tardan ~30 segundos después del primer request

### No aparecen trazas en Jaeger
1. Verificar que el microservicio usa puerto **4320** (no 4319)
2. Buscar errores `Failed to export spans` en la consola del microservicio
3. Si usa PowerShell, envolver flags `-D` en comillas

### No aparecen logs en Kibana/Elasticsearch
1. Verificar que Logstash está corriendo: `docker logs logstash --tail 20`
2. Verificar que el archivo de logs existe: `docker exec otel-collector ls -la /var/log/`
3. Verificar índice: `curl http://localhost:9200/_cat/indices?v`
4. Si el índice no existe, los microservicios aún no han enviado logs

### Error "GlobalOpenTelemetry has already been set"
El `OpenTelemetryConfig.java` ya maneja esto automáticamente. Si persiste, verificar que no hay otra clase registrando un SDK global.

### Warning "ResourceAttributes.SERVICE_NAME is deprecated"
Es un warning cosmético del SDK. No afecta funcionalidad.

---

## Notas Finales

- Los **5 dashboards de Grafana** se cargan automáticamente al iniciar el contenedor
- Las **alertas de Prometheus** se activan automáticamente
- El **Index Pattern y Dashboard de Kibana** están preconfigurados via Saved Objects API
- La **correlación logs-trazas** se logra usando el campo `traceId` que aparece en ambos sistemas
- Generar suficiente tráfico para que los gráficos muestren datos significativos

---

## 16. Guía de Validación Completa

Esta sección describe el proceso completo para levantar el sistema desde cero y confirmar que cada componente está funcionando correctamente.

---

### Fase 1 — Infraestructura Docker

**Objetivo:** Confirmar que los 8 contenedores están corriendo y sanos.

#### Paso 1.1 — Levantar los contenedores

```bash
docker compose up -d
```

#### Paso 1.2 — Verificar el estado

```bash
docker compose ps
```

**Resultado esperado:** Todos los servicios en estado `Up` o `Up (healthy)`.

| Contenedor | Estado esperado |
|------------|----------------|
| `jaeger` | `Up (healthy)` |
| `prometheus` | `Up (healthy)` |
| `elasticsearch` | `Up (healthy)` |
| `kibana` | `Up (healthy)` |
| `futurex-mysql` | `Up (healthy)` |
| `grafana` | `Up` |
| `logstash` | `Up` |
| `otel-collector` | `Up` |

#### Paso 1.3 — Verificar el OTel Collector

```bash
docker logs otel-collector --tail 5
```

**Resultado esperado:** Última línea debe decir:
```
Everything is ready. Begin running and processing data.
```

---

### Fase 2 — Microservicios

**Objetivo:** Compilar y ejecutar ambos microservicios con el Java Agent.

#### Paso 2.1 — Compilar (si no se hizo antes)

```bash
# Windows PowerShell
# Course service
cd parte0-JaegerCourseApp; .\mvnw.cmd clean package -DskipTests; cd ..

# Catalog service
cd part0-JaegerCourseCatalog; .\mvnw.cmd clean package -DskipTests; cd ..
```

#### Paso 2.2 — Iniciar fx-course-service

Abrir una **terminal nueva** y ejecutar:

```bash
# Linux / macOS
java -javaagent:opentelemetry-javaagent.jar \
     -Dotel.service.name=fx-course-service \
     -Dotel.exporter.otlp.endpoint=http://localhost:4320 \
     -Dotel.metrics.exporter=otlp \
     -Dotel.logs.exporter=otlp \
     -Dotel.traces.exporter=otlp \
     -jar parte0-JaegerCourseApp/target/FutureXCourseApp-0.0.1-SNAPSHOT.jar
```

```powershell
# Windows PowerShell
java "-javaagent:opentelemetry-javaagent.jar" `
     "-Dotel.service.name=fx-course-service" `
     "-Dotel.exporter.otlp.endpoint=http://localhost:4320" `
     "-Dotel.metrics.exporter=otlp" `
     "-Dotel.logs.exporter=otlp" `
     "-Dotel.traces.exporter=otlp" `
     -jar "parte0-JaegerCourseApp\target\FutureXCourseApp-0.0.1-SNAPSHOT.jar"
```

**Resultado esperado en consola:**
```
[otel.javaagent] opentelemetry-javaagent - version: 2.27.0
Started FutureXCourseAppApplication in XX seconds
Sample courses loaded successfully.
```

#### Paso 2.3 — Iniciar fx-catalog-service

Abrir una **segunda terminal nueva** y ejecutar:

```bash
# Linux / macOS
java -javaagent:opentelemetry-javaagent.jar \
     -Dotel.service.name=fx-catalog-service \
     -Dotel.exporter.otlp.endpoint=http://localhost:4320 \
     -Dotel.metrics.exporter=otlp \
     -Dotel.logs.exporter=otlp \
     -Dotel.traces.exporter=otlp \
     -jar part0-JaegerCourseCatalog/target/FutureXCourseCatalog-0.0.1-SNAPSHOT.jar
```

```powershell
# Windows PowerShell
java "-javaagent:opentelemetry-javaagent.jar" `
     "-Dotel.service.name=fx-catalog-service" `
     "-Dotel.exporter.otlp.endpoint=http://localhost:4320" `
     "-Dotel.metrics.exporter=otlp" `
     "-Dotel.logs.exporter=otlp" `
     "-Dotel.traces.exporter=otlp" `
     -jar "part0-JaegerCourseCatalog\target\FutureXCourseCatalog-0.0.1-SNAPSHOT.jar"
```

**Resultado esperado en consola:**
```
[otel.javaagent] opentelemetry-javaagent - version: 2.27.0
the agent provides the global OpenTelemetry object used by your application.
Started FutureXCourseCatalogApplication in XX seconds
```

#### Paso 2.4 — Verificar health checks

```bash
curl http://localhost:8001/actuator/health
curl http://localhost:8002/actuator/health
```

**Resultado esperado:** `{"status":"UP",...}`

---

### Fase 3 — Generación de Tráfico

**Objetivo:** Enviar solicitudes reales para que fluya telemetría por todo el sistema.

#### Opción A — Script automático

```powershell
powershell -ExecutionPolicy Bypass -File generate-traffic.ps1
```

#### Opción B — Requests manuales

```bash
# 1. Listar cursos (genera traza en fx-course-service)
curl http://localhost:8001/courses

# 2. Ver un curso por ID
curl http://localhost:8001/courses/1
curl http://localhost:8001/courses/2

# 3. Catálogo (genera traza DISTRIBUIDA: catalog → course)
curl http://localhost:8002/catalog
curl http://localhost:8002/firstcourse

# 4. Provocar un error 404 (para ver métricas de error)
curl http://localhost:8001/courses/999

# 5. Crear y eliminar un curso (POST y DELETE)
curl -X POST http://localhost:8001/courses \
  -H "Content-Type: application/json" \
  -d '{"courseid":10,"coursename":"Test","author":"Tester"}'
curl -X DELETE http://localhost:8001/courses/10
```

> Esperar **20-30 segundos** antes de verificar los datos en los sistemas de observabilidad.

---

### Fase 4 — Verificar Jaeger

**URL:** http://localhost:16686

1. Abrir http://localhost:16686
2. En **"Service"** seleccionar `fx-catalog-service` → **"Find Traces"**
3. ✅ Deben aparecer trazas con 2 servicios en el span (catalog → course)
4. Click en una traza → ver el **diagrama de cascada**
5. En **"Service"** seleccionar `fx-course-service` → **"Find Traces"**
6. ✅ Deben aparecer trazas individuales de los endpoints `/courses`, `/courses/{id}`
7. Copiar un **Trace ID** para usarlo en el paso de Kibana

**Señales de éxito:**
- Al menos 2 servicios listados en el dropdown
- Trazas con múltiples spans (catalog tiene un span saliente hacia course)
- Atributos visibles: `http.method`, `http.route`, `http.response_status_code`

---

### Fase 5 — Verificar Prometheus

**URL:** http://localhost:9090

#### 5.1 — Verificar targets

1. Abrir http://localhost:9090/targets
2. ✅ El target `otel-collector` debe estar **UP** (color verde)

#### 5.2 — Verificar métricas HTTP

1. Ir a http://localhost:9090 → pestaña **"Graph"**
2. Pegar y ejecutar:
```promql
otel_http_server_request_duration_seconds_count
```
3. ✅ Debe mostrar series con labels `http_route`, `service_name`, `http_response_status_code`

#### 5.3 — Verificar métricas JVM

```promql
otel_jvm_cpu_recent_utilization_ratio
```
4. ✅ Debe mostrar valores para `fx-course-service` y `fx-catalog-service`

#### 5.4 — Verificar alertas

1. Abrir http://localhost:9090/alerts
2. ✅ Las 5 alertas deben estar en estado **"Inactive"** (verde) o **"Pending"**

**Señales de éxito:**
- Target en estado UP
- Métricas HTTP con valores > 0
- JVM metrics con 2 servicios

---

### Fase 6 — Verificar Grafana

**URL:** http://localhost:3000 · Login: **admin / admin**

#### 6.1 — Abrir el dashboard general

1. Login en http://localhost:3000
2. Ir a **Dashboards** → carpeta **FutureX**
3. Abrir **"FutureX - Observabilidad General"**
4. ✅ Los paneles deben mostrar datos (no "No data")

#### 6.2 — Verificar cada dashboard

| Dashboard | URL | Qué verificar |
|-----------|-----|---------------|
| Observabilidad General | http://localhost:3000/d/futurex-observability | Panel "Solicitudes/min" con líneas de datos |
| Ejemplo 1: Requests | http://localhost:3000/d/futurex-requests-endpoint | Barras de requests por endpoint |
| Ejemplo 2: CPU/Mem | http://localhost:3000/d/futurex-resources | Gráficos de CPU y memoria no vacíos |
| Ejemplo 3: Errores | http://localhost:3000/d/futurex-errors-success | Donut con distribución de status codes |

#### 6.3 — Cambiar rango de tiempo

Si los paneles aparecen vacíos:
1. Esquina superior derecha → selector de tiempo
2. Cambiar a **"Last 15 minutes"** o **"Last 1 hour"**
3. Click en **"Refresh"** (icono ↻)

**Señales de éxito:**
- Paneles timeseries con líneas visibles
- Gauge de latencia P95 con valor
- Panel de logs recientes mostrando entradas

---

### Fase 7 — Verificar Kibana

**URL:** http://localhost:5601

> El index pattern y el dashboard están preconfigurados. No se requiere ninguna configuración manual.

#### 7.1 — Dashboard de logs

1. Abrir **http://localhost:5601/app/dashboards#/view/futurex-kibana-logs**
2. ✅ Deben aparecer 6 paneles con datos:
   - Line chart: volumen de logs por servicio en el tiempo
   - Area chart: logs de error/warning en el tiempo
   - Pie chart: proporción por servicio
   - Bar chart: distribución por nivel de severidad
   - Metric: conteo de logs con traceId real
   - Tabla: logs recientes con traceId, servicio y mensaje

#### 7.2 — Saved Searches en Discover

1. Menú lateral → **Discover**
2. Click en el icono de carpeta → **Open**
3. Seleccionar `FutureX - Logs con TraceId para Correlacion`
4. ✅ Columnas visibles: `@timestamp`, `service.name`, `log.level`, `traceId`, `Body`

#### 7.3 — Buscar logs de error con KQL

En la barra de búsqueda:
```
log.level.keyword: (WARNING OR ERROR)
```

#### 7.4 — Correlacionar con Jaeger

1. En Jaeger copiar un **Trace ID** de cualquier traza de `fx-course-service`
2. En Kibana Discover (index `otel-logs-*`):
```
traceId: "PEGAR_TRACE_ID_AQUI"
```
3. ✅ Deben aparecer **2 documentos**: uno de `fx-catalog-service` y otro de `fx-course-service` — misma traza distribuida desde ambos servicios

**Señales de éxito:**
- Dashboard abre con 6 paneles y datos reales
- Saved searches retornan logs filtrados correctamente
- Búsqueda por traceId retorna logs de ambos servicios con el mismo ID

---

### Fase 8 — Verificación Automática (script)

Ejecutar el script incluido que verifica todos los sistemas a la vez:

```powershell
powershell -ExecutionPolicy Bypass -File verify.ps1
```

**Resultado esperado:**
```
=== 1. JAEGER - Traces ===
Services found: 3
  - fx-catalog-service
  - fx-course-service
  - jaeger-all-in-one

=== 2. PROMETHEUS - Metrics ===
Metric series found: N
  - service=fx-... route=/catalog value=X

=== 3. PROMETHEUS - JVM Metrics ===
JVM CPU series: 4

=== 4. ELASTICSEARCH - Logs ===
Log documents indexed: N  (debe ser > 0)

=== 5. GRAFANA - Dashboards ===
Dashboards found: 5
  - FutureX - Ejemplo 1: ...
  - FutureX - Ejemplo 2: ...
  - FutureX - Ejemplo 3: ...
  - FutureX - Observabilidad General
```

---

### Resumen de verificación

| # | Sistema | URL | Señal de éxito |
|---|---------|-----|----------------|
| 1 | Infraestructura | `docker compose ps` | Todos los contenedores `Up` |
| 2 | OTel Collector | `docker logs otel-collector` | `Everything is ready` |
| 3 | Microservicios | http://localhost:8001/actuator/health | `{"status":"UP"}` |
| 4 | **Jaeger** | http://localhost:16686 | 2 servicios + trazas distribuidas |
| 5 | **Prometheus** | http://localhost:9090/targets | Target `otel-collector` en **UP** |
| 6 | **Grafana** | http://localhost:3000 | 5 dashboards con datos |
| 7 | **Kibana** | http://localhost:5601 | Logs indexados en `otel-logs-*` |
| 8 | Script | `final-check.ps1` | Todos los checks en verde |

---

## 17. Resumen Final de Implementación

> **Estado validado:** 25 Mayo 2026 — Verificación final completa. Todo el stack funciona correctamente.

### ¿Qué se implementó?

| Componente | Descripción |
|-----------|-------------|
| **OTel Collector** | Recibe trazas/métricas/logs via OTLP HTTP (4318) y gRPC (4317). Exporta a Jaeger, Prometheus y archivo de logs |
| **Java Agent 2.27.0** | Instrumentación automática de ambos microservicios. Genera métricas JVM, HTTP y DB sin código adicional |
| **Prometheus** | Scrapea métricas del Collector en puerto 8889. Label clave: `exported_job` (no `service_name`) |
| **Grafana** | 5 dashboards + 5 alertas provisionados automáticamente |
| **Jaeger** | Recibe trazas via OTLP gRPC. 3 servicios instrumentados |
| **ELK Stack** | Logstash lee `/var/log/otel-collector.log`, parsea JSON y envía a Elasticsearch. Kibana visualiza |

---

### Dashboards en Grafana

#### Dashboard 1 — Ejemplo 1: Solicitudes por Endpoint
**URL:** http://localhost:3000/d/futurex-requests-endpoint

| Panel | Tipo | Qué muestra | Cómo leerlo |
|-------|------|-------------|-------------|
| Solicitudes/min por Endpoint | Timeseries | Req/min para cada ruta HTTP (`/courses`, `/catalog`, `/firstcourse`, etc.) | Picos = tráfico intenso. Sin líneas = sin tráfico. |
| Solicitudes/min fx-catalog-service | Timeseries | Req/min solo de catalog por endpoint | Permite comparar `/catalog` vs `/firstcourse` |
| Solicitudes/min fx-course-service | Timeseries | Req/min solo de course por endpoint | Permite comparar `/courses` vs `/{id}` vs 404s |
| Solicitudes Totales por Servicio (1h) | Stat | Total acumulado de requests en 1 hora por servicio | Número absoluto, útil para dimensionar carga |
| Solicitudes por Método HTTP | Piechart | Distribución GET vs POST vs DELETE | Confirma que el tráfico es principalmente GET |

**Métrica usada:** `otel_http_server_request_duration_seconds_count` con label `http_route`, `exported_job`, `http_request_method`

---

#### Dashboard 2 — Ejemplo 2: CPU y Memoria
**URL:** http://localhost:3000/d/futurex-resources

| Panel | Tipo | Qué muestra | Cómo leerlo |
|-------|------|-------------|-------------|
| Uso de CPU por Servicio | Timeseries | % de CPU JVM (0–100%) por servicio en el tiempo | >80% sostenido indica sobrecarga. Picos breves son normales. |
| Uso de Memoria JVM (Heap) | Timeseries | MB de heap usados por cada servicio | Crecimiento continuo sin bajadas = posible memory leak. Bajadas = GC actuó. |
| Threads JVM por Servicio | Timeseries | Número de threads activos en cada JVM | Crecimiento sostenido sin techo = thread leak. Normal: 20–60 threads. |
| CPU Actual (Gauge) | Gauge | % CPU instantáneo, semáforo verde/amarillo/rojo | Verde <50%, Amarillo <80%, Rojo >80% |
| Memoria Heap Actual (Gauge) | Gauge | % heap used/committed instantáneo | Verde <70%, Amarillo <85%, Rojo >85% |
| Garbage Collection — Duración | Timeseries | Tiempo acumulado de GC en ms | Picos de GC = presión de memoria. Correlacionar con latencia alta. |

**Métricas usadas:** `otel_jvm_cpu_recent_utilization_ratio`, `otel_jvm_memory_used_bytes`, `otel_jvm_thread_count`, `otel_jvm_gc_duration_seconds`

---

#### Dashboard 3 — Ejemplo 3: Errores vs Éxitos
**URL:** http://localhost:3000/d/futurex-errors-success

| Panel | Tipo | Qué muestra | Cómo leerlo |
|-------|------|-------------|-------------|
| Errores vs Éxitos — Distribución (6h) | Piechart | Proporción 2xx / 3xx / 4xx / 5xx en las últimas 6h | Verde = éxitos, Naranja = errores cliente, Rojo = errores servidor |
| Tasa de Error (%) en el tiempo | Timeseries | % de requests con error (4xx+5xx) sobre total | >5% sostenido es preocupante. Los 404s de `/courses/999` son visibles aquí. |
| Errores vs Éxitos por Servicio | Timeseries | Comparación de requests ok vs errores por servicio | Ver si los errores se concentran en un servicio específico |
| Correlación: Errores vs Latencia | Timeseries (eje dual) | Tasa de error % (izq.) + P95 latencia en ms (der.) | Si ambas suben juntas → hay sobrecarga. Si error sube pero latencia no → errores lógicos (404s, validaciones). |
| Status Codes por Endpoint (6h) | Tabla | Conteo de requests por endpoint y código HTTP | Identifica qué endpoint genera más errores y qué código devuelven. |

**Métricas usadas:** `otel_http_server_request_duration_seconds_count` con `http_response_status_code`

---

#### Dashboard 4 — Observabilidad General
**URL:** http://localhost:3000/d/futurex-observability

| Panel | Tipo | Qué muestra | Cómo leerlo |
|-------|------|-------------|-------------|
| Solicitudes/min por Endpoint | Timeseries | Vista global de tráfico por ruta | Panel de entrada, vista rápida de actividad |
| Latencia Promedio por Endpoint (ms) | Timeseries | ms promedio por ruta en ventana 5min | >500ms indica problema. Normal: <100ms |
| Errores vs Éxitos | Piechart | Distribución de status codes global | Debe ser >95% verde en operación normal |
| Total Solicitudes por Servicio (1h) | Stat | Req acumulados por servicio | Comparativa rápida de carga entre servicios |
| Latencia P95 | Gauge | Percentil 95 de latencia global | Semáforo: verde <500ms, amarillo <2000ms, rojo >2000ms |
| CPU por Servicio (%) | Timeseries | CPU JVM ambos servicios | Detección rápida de sobrecarga |
| Memoria Heap por Servicio | Timeseries | Heap en MB ambos servicios | Detección rápida de memory pressure |

**Métricas usadas:** combinación de HTTP server, JVM CPU y Heap

---

#### Dashboard 5 — Avanzado: Anomalías y Correlación
**URL:** http://localhost:3000/d/futurex-advanced

| Panel | Tipo | Qué muestra | Cómo leerlo |
|-------|------|-------------|-------------|
| Detección de Anomalías — Tasa de Error | Timeseries | Error rate % con líneas de umbral 5% (naranja) y 10% (rojo) | Cuando la línea sube sobre los umbrales → comportamiento anormal. Los 404s de `/courses/999` son visibles. |
| Correlación: Latencia P95 vs Error | Timeseries (eje dual) | P95 ms (izq.) + error rate % (der.) en el tiempo | Si ambas suben juntas → sobrecarga del sistema. Si solo error sube → errores lógicos. |
| Correlación: CPU JVM vs Latencia | Timeseries (eje dual) | CPU % (izq.) por servicio + latencia promedio ms (der.) | CPU alto + latencia alta → cuello de botella en CPU de la JVM |
| Throughput por Endpoint (req/min) | Bargauge horizontal | Req/min actual por endpoint, ordenado desc | Identifica qué endpoints reciben más carga. Gradiente de color por intensidad. |
| Latencia P50 vs P95 vs P99 | Timeseries | Tres percentiles en el mismo panel | Si P99 >> P50 → hay tail latency (requests lentos esporádicos). Diferencia grande = variabilidad alta. |
| Correlación: Heap JVM vs Throughput | Timeseries (eje dual) | Heap MB (izq.) + req/min (der.) | Heap que crece proporcionalmente al throughput indica buen comportamiento. Heap que crece sin throughput = leak. |
| Tabla: Métricas por Endpoint | Tabla | Req/min por endpoint + servicio + status code, instantáneo | Vista tabular para identificar endpoints problemáticos de un vistazo |
| Tasa de Requests: Catálogo vs Cursos | Timeseries | Req/min de cada servicio en el tiempo | Comparación directa: divergencia sostenida indica degradación en uno de ellos |
| Gauge: Estado Actual del Sistema | Stat (semáforo) | 4 métricas simultáneas: Error Rate %, P95 ms, CPU Max %, Heap % | Verde = normal, Amarillo = advertencia, Rojo = crítico. Vista instantánea de salud del sistema. |
| Conexiones DB: Activas vs Idle | Timeseries | Pool HikariCP: used / idle / max (fx-course-service) | `used` alto y `idle` bajo → contención de BD. Si `used` = `max` → pool saturado. |
| Threads JVM por Servicio | Timeseries | Threads activos en ambas JVMs | Crecimiento sostenido sin techo = thread leak. |

**Métricas usadas:** todas las `otel_*` disponibles incluyendo histograma, JVM, DB pool

**URLs directas:**
- http://localhost:3000/d/futurex-requests-endpoint
- http://localhost:3000/d/futurex-resources
- http://localhost:3000/d/futurex-errors-success
- http://localhost:3000/d/futurex-observability
- http://localhost:3000/d/futurex-advanced

---

### Alertas en Grafana

| UID | Título | Condición | Severidad |
|-----|--------|-----------|-----------|
| `fx-high-error-rate` | Alta Tasa de Errores HTTP | Error rate > 10% por 2 min | warning |
| `fx-high-latency` | Alta Latencia P95 | P95 > 2000ms por 3 min | critical |
| `fx-no-traffic` | Sin Tráfico HTTP | rate < 0.001 req/s por 10 min | info |
| `fx-high-cpu` | CPU Alto en Microservicio | CPU JVM > 85% por 2 min | warning |
| `fx-heap-pressure` | Presión de Memoria Heap | Heap > 90% committed por 5 min | critical |

Ver alertas en: http://localhost:3000/alerting/list

---

### Queries Prometheus verificados (label: `exported_job`)

```promql
# Requests por minuto por servicio
sum(rate(otel_http_server_request_duration_seconds_count[1m])) by (exported_job) * 60

# Latencia promedio en ms
rate(otel_http_server_request_duration_seconds_sum[5m]) / rate(otel_http_server_request_duration_seconds_count[5m]) * 1000

# Tasa de errores %
(sum(rate(otel_http_server_request_duration_seconds_count{http_response_status_code=~"[45].."}[5m])) / sum(rate(otel_http_server_request_duration_seconds_count[5m]))) * 100

# Latencia P95
histogram_quantile(0.95, sum(rate(otel_http_server_request_duration_seconds_bucket[5m])) by (le, exported_job))

# CPU por servicio
otel_jvm_cpu_recent_utilization_ratio{exported_job="fx-catalog-service"} * 100

# Heap usado por servicio
sum(otel_jvm_memory_used_bytes{jvm_memory_type="heap"}) by (exported_job)
```

> Documento completo: `docs/queries-prometheus.md` (18 queries validados)

---

### Queries Elasticsearch verificados (índice: `otel-logs-*`)

```json
// Errores últimas 24h (KQL en Kibana Discover)
log.level: ERROR OR log.level: WARNING

// Logs de un servicio
service.name: "fx-course-service"

// Correlación por traceId
traceId: "PEGAR_ID_DE_JAEGER"

// Logs con traza (requests reales)
traceId: *
```

> Documento completo: `docs/queries-elasticsearch.md` (12 queries validados)

---

### Cómo levantar el proyecto

```powershell
# 1. Levantar infraestructura
docker compose up -d

# 2. Iniciar microservicios (en terminales separadas)
java -javaagent:opentelemetry-javaagent.jar `
  -Dotel.service.name=fx-course-service `
  -Dotel.exporter.otlp.endpoint=http://localhost:4318 `
  -jar parte0-JaegerCourseApp\target\FutureXCourseApp-0.0.1-SNAPSHOT.jar

java -javaagent:opentelemetry-javaagent.jar `
  -Dotel.service.name=fx-catalog-service `
  -Dotel.exporter.otlp.endpoint=http://localhost:4318 `
  -jar parte0-CatalogApp\target\FutureXCatalogApp-0.0.1-SNAPSHOT.jar

# 3. Generar tráfico
powershell -File generate-traffic-heavy.ps1

# 4. Verificar todo
powershell -File final-verify.ps1
```

---

### URLs de acceso

| Herramienta | URL | Credenciales |
|-------------|-----|--------------|
| **Jaeger** (trazas) | http://localhost:16686 | — |
| **Prometheus** (métricas) | http://localhost:9090 | — |
| **Grafana** (dashboards) | http://localhost:3000 | admin / admin |
| **Kibana** (logs) | http://localhost:5601 | — |
| **Elasticsearch** (API) | http://localhost:9200 | — |
| **fx-course-service** | http://localhost:8001 | — |
| **fx-catalog-service** | http://localhost:8002 | — |
| **OTel Collector metrics** | http://localhost:8889/metrics | — |

---

### Qué ver en cada herramienta

**Jaeger** → `http://localhost:16686`
- Service: `fx-course-service` o `fx-catalog-service`
- Operaciones: `GET /courses`, `GET /catalog`, `GET /{id}`
- Trazas con spans anidados si hay llamadas entre servicios

**Prometheus** → `http://localhost:9090`
- Status → Targets: target `otel-collector` en **UP**
- Graph: pegar cualquier query de `docs/queries-prometheus.md`
- Métricas con prefijo `otel_jvm_*`, `otel_http_*`, `otel_db_*`

**Grafana** → `http://localhost:3000` (admin/admin)
- Dashboards → Browse → carpeta **FutureX**
- Alerting → Alert rules → 5 reglas activas en carpeta **FutureX**
- Todos los paneles muestran datos reales con label `exported_job`

**Kibana** → `http://localhost:5601`
- Discover → index pattern `otel-logs-*`
- Campos disponibles: `service.name`, `log.level`, `Body`, `traceId`, `severityNumber`
- KQL: `log.level: WARNING` para ver logs del OTel Collector y microservicios

---

### Validación rápida en 5 pasos

```powershell
# 1. Todos los contenedores Up
docker compose ps

# 2. Métricas llegando a Prometheus
Invoke-WebRequest "http://localhost:9090/api/v1/query?query=otel_http_server_request_duration_seconds_count" | ConvertFrom-Json | Select -ExpandProperty data

# 3. Logs en Elasticsearch
Invoke-WebRequest "http://localhost:9200/otel-logs-*/_count" | ConvertFrom-Json

# 4. Trazas en Jaeger
Invoke-WebRequest "http://localhost:16686/api/services" | ConvertFrom-Json

# 5. Script completo de verificacion final
powershell -File final-check.ps1
```

---


### Partes avanzadas implementadas

| Funcionalidad | Estado | Evidencia |
|--------------|--------|-----------|
| 5 dashboards Grafana (incluyendo avanzado) | ✅ | `/d/futurex-advanced` con 11 panels |
| Detección de anomalías (umbral visual) | ✅ | Panel 1 de `futurex-advanced` |
| Correlación CPU vs Latencia | ✅ | Panel 3 de `futurex-advanced` (eje dual) |
| Correlación Heap vs Throughput | ✅ | Panel 6 de `futurex-advanced` |
| Percentiles P50/P95/P99 | ✅ | Panel 5 de `futurex-advanced` |
| Gauge semáforo de estado (4 métricas) | ✅ | Panel 9 de `futurex-advanced` |
| Bargauge comparativo por endpoint | ✅ | Panel 4 de `futurex-advanced` |
| Tabla de métricas por endpoint | ✅ | Panel 7 de `futurex-advanced` |
| Monitoreo pool DB HikariCP | ✅ | `otel_db_client_connections_usage` (idle=10) |
| Threads JVM por servicio | ✅ | `otel_jvm_thread_count` |
| GC duration por servicio | ✅ | `otel_jvm_gc_duration_seconds` |
| 5 alertas Grafana activas | ✅ | `fx-high-error-rate`, `fx-high-latency`, `fx-no-traffic`, `fx-high-cpu`, `fx-heap-pressure` |
| Correlación logs↔trazas (traceId en ES) | ✅ | 809 docs con traceId real en ES |
| Logs por logRecord individual (no por batch) | ✅ | Logstash `split` pipeline |
| Errores HTTP 4xx reales en métricas | ✅ | `http_response_status_code=404` visible en Prometheus |
| Trazas distribuidas catalog→course | ✅ | Mismo traceId en ambos servicios en Jaeger y ES |
| Dashboard Kibana con 6 visualizaciones | ✅ | Line, Area, Pie, Bar, Metric, Saved Search — `futurex-kibana-logs` |

---


### Validaciones realizadas

**Prometheus:**
- 22 métricas `otel_*` activas
- 8 métricas clave verificadas con datos reales
- Errores 404 reales visibles (`http_response_status_code=404`)
- P95 latencia: ~47ms (datos reales)
- Req/min: ~36 (tráfico generado)
- CPU, Heap, Threads, DB pool — todos con valores reales

**Elasticsearch:**
- 1000+ documentos indexados
- `fx-course-service` y `fx-catalog-service` — ambos indexados
- 809 documentos con `traceId` real y no vacío
- Niveles: INFO, WARNING — campos `service.name`, `log.level`, `Body`, `traceId`, `@timestamp` todos presentes
- Correlación confirmada: mismo traceId en logs de ambos servicios cuando catalog llama a course

**Jaeger:**
- `fx-course-service`: 14 operaciones (HTTP server, SQL client, Hibernate internal, DB TX)
- `fx-catalog-service`: 4 operaciones (HTTP server + HTTP client call a course-service)
- Trazas distribuidas confirmadas con propagación W3C TraceContext

**Grafana:**
- 5 dashboards cargados vía provisioning
- 5 alertas activas evaluándose cada minuto
- 3 datasources: Prometheus (uid=`prometheus`), Elasticsearch, Jaeger
- Sin paneles rotos en ningún dashboard

---

### Scripts disponibles

| Script | Uso |
|--------|-----|
| `generate-traffic.ps1` | Genera 45 requests HTTP variados a ambos microservicios |
| `generate-traffic-heavy.ps1` | Genera tráfico intensivo (5 rondas × 9 endpoints = 45 requests) incluyendo 404s |
| `final-check.ps1` | Verificación completa del stack: infraestructura, métricas, ES, Jaeger, Grafana |

---

### Cómo validar manualmente todo el taller

**Paso 1 — Infraestructura:**
```powershell
docker compose ps
# Esperado: 8 contenedores Up
```

**Paso 2 — Generar tráfico:**
```powershell
powershell -File generate-traffic-heavy.ps1
```

**Paso 3 — Prometheus** → http://localhost:9090
- Status → Targets → `otel-collector` en **UP**
- Graph → `sum(rate(otel_http_server_request_duration_seconds_count[1m])) by (exported_job) * 60`

**Paso 4 — Jaeger** → http://localhost:16686
- Service: `fx-course-service` → Find Traces → ver spans anidados con SQL

**Paso 5 — Grafana** → http://localhost:3000 (admin/admin)
- Dashboards → Browse → carpeta FutureX → 5 dashboards
- Alerting → Alert rules → 5 reglas activas
- Dashboard avanzado: http://localhost:3000/d/futurex-advanced

**Paso 6 — Kibana** → http://localhost:5601
- Dashboard: http://localhost:5601/app/dashboards#/view/futurex-kibana-logs → 6 paneles con datos
- Discover → Open → `FutureX - Logs con TraceId para Correlacion`
- Correlación: copiar traceId de Jaeger → buscar en Kibana: `traceId: "VALOR"` → retorna logs de ambos servicios

**Paso 7 — Verificación automática:**
```powershell
powershell -File final-check.ps1
# Esperado: todos los checks [OK]
```
