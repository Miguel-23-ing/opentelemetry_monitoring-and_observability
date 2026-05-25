# Queries de Elasticsearch / Kibana

## Documentación de queries funcionales para búsqueda de logs en ELK

Acceso: **Kibana** http://localhost:5601 → Dev Tools / Discover  
API REST: **Elasticsearch** http://localhost:9200

> **VALIDADO**: Campos verificados contra el mapping real del índice `otel-logs-*`.

### Índice y campos disponibles (VERIFICADOS)

| Campo | Tipo ES | Descripción | Ejemplo |
|-------|---------|-------------|--------|
| `service.name` | text | Nombre del microservicio | `fx-catalog-service` |
| `log.level` | text | Nivel de severidad | `INFO`, `WARN`, `WARNING`, `ERROR` |
| `Body` | text | Mensaje del log | `"Request received at /catalog..."` |
| `traceId` | text | ID de traza distribuida | `abc123def456...` |
| `spanId` | text | ID del span actual | `789ghi...` |
| `severityNumber` | long | Nivel numérico | `9`=INFO, `13`=WARN, `17`=ERROR |
| `@timestamp` | date | Timestamp del evento | `2026-05-25T00:06:02.543Z` |
| `host` | text | Host del proceso | `f5fda64c355e` |
| `path` | text | Archivo de origen del log | `/var/log/otel-collector.log` |

> **Nota sobre `.keyword`**: Para usar un campo en agregaciones o filtros exactos,
> añadir `.keyword` al nombre: `service.name.keyword`, `log.level.keyword`.

**Índice**: `otel-logs-*` (se crea automáticamente cuando Logstash envía el primer log)

---

## 1. Logs ERROR/WARNING en últimas 24h

**Qué muestra:** Todos los logs con nivel ERROR o WARNING de ambos microservicios en las últimas 24 horas.
**Cuándo usarlo:** Primera consulta para diagnóstico. Si el sistema tiene problemas, aquí aparecerán los errores con su timestamp y traceId.
**Cómo leerlo:** El campo `Body` contiene el mensaje completo. El campo `traceId` permite ir a Jaeger y ver la traza donde ocurrió el error.

```json
GET /otel-logs-*/_search
{
  "query": {
    "bool": {
      "must": [
        {
          "bool": {
            "should": [
              { "match": { "log.level": "ERROR" } },
              { "match": { "log.level": "WARNING" } }
            ]
          }
        },
        { "range": { "@timestamp": { "gte": "now-24h" } } }
      ]
    }
  },
  "sort": [{ "@timestamp": { "order": "desc" } }],
  "size": 50,
  "_source": ["@timestamp", "service.name", "log.level", "Body", "traceId", "spanId"]
}
```

**KQL equivalente en Kibana Discover:**
```
log.level: ERROR OR log.level: WARNING
```

### Variante: Errores de un servicio específico
```json
GET /otel-logs-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "service.name": "fx-course-service" } },
        { "match": { "log.level": "ERROR" } },
        { "range": { "@timestamp": { "gte": "now-24h" } } }
      ]
    }
  },
  "sort": [{ "@timestamp": { "order": "desc" } }],
  "size": 50,
  "_source": ["@timestamp", "service.name", "Body", "traceId"]
}
```

**KQL:** `service.name: "fx-course-service" AND log.level: ERROR`

---

## 2. Logs por servicio — últimas 2 horas

**Qué muestra:** Todos los logs (cualquier nivel) generados por un servicio específico en las últimas 2 horas.
**Cuándo usarlo:** Para inspeccionar la actividad completa de un servicio — útil al hacer trazabilidad de un bug.
**Cómo leerlo:** Cambia `fx-catalog-service` por `fx-course-service` para ver el otro servicio. Ordenados por timestamp desc = más reciente primero.

**KQL (Kibana Discover):** `service.name: "fx-catalog-service"`

```json
GET /otel-logs-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "service.name": "fx-catalog-service" } },
        { "range": { "@timestamp": { "gte": "now-2h" } } }
      ]
    }
  },
  "sort": [{ "@timestamp": { "order": "desc" } }],
  "size": 100,
  "_source": ["@timestamp", "service.name", "log.level", "Body", "traceId"]
}
```

---

## 3. Logs WARN/WARNING de todos los servicios

**Qué muestra:** Solo los logs de advertencia de ambos servicios en las últimas 6 horas.
**Cuándo usarlo:** Los warnings más frecuentes son internos del OTel Collector (exportación de métricas). Si ves warnings de negocio (ej: "Course not found"), hay algo que revisar en la aplicación.
**Cómo leerlo:** Revisa el campo `Body`. Si dice `"Failed to export"` → es ruido interno del Collector. Si menciona endpoints o entidades → es un warning real de la app.

> **Nota**: El Java Agent 2.x usa `WARNING` (no `WARN`). Ambas variantes están incluidas.

**KQL:** `log.level: WARNING OR log.level: WARN`

```json
GET /otel-logs-*/_search
{
  "query": {
    "bool": {
      "should": [
        { "match": { "log.level": "WARNING" } },
        { "match": { "log.level": "WARN" } }
      ],
      "minimum_should_match": 1,
      "filter": [
        { "range": { "@timestamp": { "gte": "now-6h" } } }
      ]
    }
  },
  "sort": [{ "@timestamp": { "order": "desc" } }],
  "size": 50,
  "_source": ["@timestamp", "service.name", "Body", "traceId"]
}
```

---

## 4. Búsqueda por traceId (correlación logs-trazas)

**Qué muestra:** Todos los logs generados durante una traza distribuida específica, ordenados cronológicamente.
**Cuándo usarlo:** Después de identificar una traza lenta o errónea en Jaeger, pegar su traceId aquí para ver todos los logs relacionados.
**Cómo leerlo:** Con `sort: asc` verás el flujo completo en orden: primero el log de `fx-catalog-service` recibiendo el request, luego el log de `fx-course-service` procesando la llamada interna. Si una traza tiene 2 docs = traza distribuida correcta.

Busca todos los logs asociados a una traza específica para reconstruir el flujo completo.

```json
GET /otel-logs-*/_search
{
  "query": {
    "term": { "traceId": "<PEGAR_TRACE_ID_DE_JAEGER_AQUI>" }
  },
  "sort": [{ "@timestamp": { "order": "asc" } }],
  "size": 100,
  "_source": ["@timestamp", "service.name", "log.level", "Body", "spanId"]
}
```

> **Tip**: Obtener un traceId real desde Jaeger UI (http://localhost:16686) y pegarlo aquí.

---

## 5. Correlación entre errores y endpoints

**Qué muestra:** Logs de error cuyo mensaje (`Body`) menciona un endpoint o término específico.
**Cuándo usarlo:** Para correlacionar errores con endpoints: ¿los errores de `/catalog` son culpa del endpoint o de la llamada interna a course-service?
**Cómo leerlo:** Si el `Body` menciona `/catalog` y el `service.name` es `fx-catalog-service` → el error es propio. Si el `service.name` es `fx-course-service` → el error viene de la llamada interna.

Busca logs de error que contengan un endpoint o mensaje específico.

**KQL:** `log.level: ERROR AND Body: "/catalog"`

```json
GET /otel-logs-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "log.level": "ERROR" } },
        { "match": { "Body": "catalog" } },
        { "range": { "@timestamp": { "gte": "now-6h" } } }
      ]
    }
  },
  "sort": [{ "@timestamp": { "order": "desc" } }],
  "size": 50,
  "_source": ["@timestamp", "service.name", "Body", "traceId", "spanId"]
}
```

### Buscar errores 404 (recursos no encontrados)
```json
GET /otel-logs-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "Body": "404" } },
        { "range": { "@timestamp": { "gte": "now-6h" } } }
      ]
    }
  },
  "sort": [{ "@timestamp": { "order": "desc" } }],
  "size": 50
}
```

---

## 6. Errores más frecuentes (agregación por servicio)

**Qué muestra:** Agrupación de errores por servicio y por hora — cuántos errores tuvo cada servicio y en qué período.
**Cuándo usarlo:** Para entender la distribución temporal de errores. Si los errores se concentran en una hora específica → hubo un incidente puntual. Si están distribuidos uniformemente → hay un problema persistente.
**Cómo leerlo:** El bucket `errores_por_servicio` da el conteo por servicio. El bucket `errores_por_hora` da la curva temporal. Respuesta de `doc_count=0` en todas las horas = sin errores reales (buena señal).

Agrupa errores por servicio. Usa `severityNumber >= 17` para ERROR (compatible con todos los formatos).

```json
GET /otel-logs-*/_search
{
  "size": 0,
  "query": {
    "bool": {
      "should": [
        { "match": { "log.level": "ERROR" } },
        { "range": { "severityNumber": { "gte": 17 } } }
      ],
      "minimum_should_match": 1,
      "filter": [
        { "range": { "@timestamp": { "gte": "now-24h" } } }
      ]
    }
  },
  "aggs": {
    "errores_por_servicio": {
      "terms": {
        "field": "service.name.keyword",
        "size": 10
      }
    },
    "errores_por_hora": {
      "date_histogram": {
        "field": "@timestamp",
        "calendar_interval": "1h"
      }
    }
  }
}
```

---

## 7. Servicios con más logs (volumen por servicio)

**Qué muestra:** Ranking de servicios por volumen de logs, con desglose de nivel por servicio.
**Cuándo usarlo:** Para entender quién genera más ruido. En condiciones normales: ambos servicios deberían estar ~50/50. Si uno genera 10x más → puede haber un bucle de logs o un error que se repite.
**Cómo leerlo:** Cada bucket tiene `key` (nombre servicio) y dentro tiene `logs_por_nivel` con los sub-buckets por nivel. Comparar cuantos WARNING/INFO tiene cada uno.

```json
GET /otel-logs-*/_search
{
  "size": 0,
  "query": {
    "range": { "@timestamp": { "gte": "now-1h" } }
  },
  "aggs": {
    "logs_por_servicio": {
      "terms": {
        "field": "service.name.keyword",
        "size": 10
      },
      "aggs": {
        "logs_por_nivel": {
          "terms": {
            "field": "log.level.keyword",
            "size": 5
          }
        }
      }
    }
  }
}
```

---

## 8. Conteo de logs por nivel de severidad

**Qué muestra:** Distribución de todos los logs por nivel — cuántos son INFO, WARNING, ERROR, etc. en la última hora.
**Cuándo usarlo:** Para tener una foto instantánea de la salud del sistema. En operación normal: WARNING domina (internos del Collector), INFO segundo (requests de negocio), ERROR = 0.
**Cómo leerlo:** `por_nivel_texto` usa el campo texto (`INFO`, `WARNING`). `por_severity_number` usa el número OTLP (9=INFO, 13=WARNING, 17=ERROR). Ambas agruparán los mismos docs.

```json
GET /otel-logs-*/_search
{
  "size": 0,
  "query": {
    "range": { "@timestamp": { "gte": "now-1h" } }
  },
  "aggs": {
    "por_nivel_texto": {
      "terms": { "field": "log.level.keyword", "size": 10 }
    },
    "por_severity_number": {
      "histogram": { "field": "severityNumber", "interval": 4 }
    }
  }
}
```

> Mapping `severityNumber`: 9=INFO, 13=WARN/WARNING, 17=ERROR, 21=FATAL

---

## 9. Logs recientes (últimos 15 minutos)

**Qué muestra:** Los 100 logs más recientes de cualquier nivel y servicio.
**Cuándo usarlo:** Para verificar que los logs están llegando en tiempo real. Si no aparecen docs → o no hay tráfico o Logstash no está procesando.
**Cómo leerlo:** Si `hits.total.value = 0` después de generar tráfico → problema con el pipeline Logstash. Esperar 20–30 segundos tras el tráfico para que Logstash procese.

```json
GET /otel-logs-*/_search
{
  "query": {
    "range": { "@timestamp": { "gte": "now-15m" } }
  },
  "sort": [{ "@timestamp": { "order": "desc" } }],
  "size": 100
}
```

---

## 10. Buscar logs por contenido del Body (full-text search)

**Qué muestra:** Logs cuyo campo `Body` contiene una palabra o frase específica.
**Cuándo usarlo:** Para buscar logs de un evento de negocio específico. Ej: buscar `"saved"` para ver cuándo se creó un curso, o `"courses/999"` para ver los 404 generados.
**Cómo leerlo:** El `highlight` resalta la palabra buscada en el resultado. El campo `Body` de los logs de negocio tiene el formato: `"Request received at /courses endpoint - traceId=..."`. Búsquedas útiles: `"catalog"`, `"course"`, `"firstcourse"`.

**KQL:** `Body: "course" AND Body: "saved"`

```json
GET /otel-logs-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "Body": "course" } },
        { "range": { "@timestamp": { "gte": "now-1h" } } }
      ]
    }
  },
  "sort": [{ "@timestamp": { "order": "desc" } }],
  "size": 50,
  "highlight": {
    "fields": { "Body": {} }
  }
}
```

---

## 11. Logs con traceId presente (solicitudes instrumentadas)

**Qué muestra:** Solo los logs que tienen un `traceId` válido — son los generados por requests HTTP reales instrumentados.
**Cuándo usarlo:** Para separar los logs de negocio (con traceId) de los logs internos del Collector (sin traceId). Los logs con traceId son los que tienen valor para correlación.
**Cómo leerlo:** `exists: traceId` + `must_not: traceId=""` garantiza que el campo existe Y tiene un valor real (32 caracteres hex). Valor verificado: 834 docs con traceId real en 3 horas de actividad.

Filtra solo logs que tienen traceId — estos vienen de requests HTTP reales.

**KQL:** `traceId: *`

```json
GET /otel-logs-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "exists": { "field": "traceId" } },
        { "range": { "@timestamp": { "gte": "now-1h" } } }
      ],
      "must_not": [
        { "term": { "traceId": "" } }
      ]
    }
  },
  "sort": [{ "@timestamp": { "order": "desc" } }],
  "size": 50,
  "_source": ["@timestamp", "service.name", "log.level", "Body", "traceId", "spanId"]
}
```

---

## 12. Timeline de actividad — logs por minuto

**Qué muestra:** Histograma de logs por minuto en las últimas 6 horas, desglosado por servicio.
**Cuándo usarlo:** Para detectar picos de actividad o caídas de tráfico. Es el equivalente a la gráfica de "Volumen de Logs en el Tiempo" del dashboard de Kibana pero con datos exactos por minuto.
**Cómo leerlo:** Cada bucket tiene `key_as_string` (timestamp) y `doc_count` (logs ese minuto), más sub-buckets por servicio. Un minuto con doc_count=0 puede indicar caída del servicio o simplemente ausencia de tráfico.

Muestra la distribución temporal de logs para detectar picos o caídas.

```json
GET /otel-logs-*/_search
{
  "size": 0,
  "query": {
    "range": { "@timestamp": { "gte": "now-6h" } }
  },
  "aggs": {
    "logs_por_minuto": {
      "date_histogram": {
        "field": "@timestamp",
        "fixed_interval": "1m"
      },
      "aggs": {
        "por_servicio": {
          "terms": { "field": "service.name.keyword", "size": 5 }
        }
      }
    }
  }
}
```

---

## Cómo ejecutar estos queries

### Desde Kibana Dev Tools
1. Acceder a http://localhost:5601
2. Ir a menú lateral → **Dev Tools**
3. Pegar el query completo (con `GET /otel-logs-*/_search`)
4. Click en el botón ▶️ (Play) para ejecutar

### Desde Kibana Discover
1. Ir a menú lateral → **Discover**
2. Seleccionar Index Pattern `otel-logs-*`
3. Usar la barra de búsqueda con KQL:
   - `log.level: ERROR OR log.level: WARNING` → todos los errores
   - `service.name: "fx-catalog-service"` → logs del catálogo
   - `service.name: "fx-course-service" AND log.level: WARNING` → warnings de cursos
   - `traceId: "abc123..."` → todos los logs de una traza específica
   - `Body: "Exception"` → logs con excepciones
   - `severityNumber >= 13` → WARN y superiores
4. Añadir columnas en la tabla: `service.name`, `log.level`, `Body`, `traceId`

### Desde cURL
```bash
curl -X GET "http://localhost:9200/otel-logs-*/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "bool": {
        "must": [
          { "match": { "service.name": "fx-catalog-service" } },
          { "match": { "log.level": "ERROR" } },
          { "range": { "@timestamp": { "gte": "now-24h" } } }
        ]
      }
    },
    "size": 10
  }'
```

---

## Acceso a Kibana

> El index pattern `otel-logs-*` y el dashboard están **preconfigurados** — no requieren configuración manual.

1. **Dashboard principal:** http://localhost:5601/app/dashboards#/view/futurex-kibana-logs
2. **Discover + Saved Search:** Menú lateral → Discover → carpeta → `FutureX - Logs con TraceId para Correlacion`
3. **Dev Tools** (para los queries JSON de esta página): Menú lateral → Dev Tools → pegar query → ▶️

---

## Notas importantes

- **Índice automático**: Se crea cuando Logstash envía el primer log a ES
- **Campos `.keyword`**: Para agregaciones y filtros exactos usar `service.name.keyword` (no `service.name`)
- **Campos anidados**: Si un campo no aparece, verificar en el mapping: `GET /otel-logs-*/_mapping`
- **Correlación**: Usar `traceId` para vincular logs con trazas en Jaeger
- **Volumen**: El campo `sincedb_path => "/dev/null"` en Logstash relee el archivo completo en cada reinicio
