# Load tests con k6

Pruebas de carga para validar capacidad real de testexamen.es bajo distintos
escenarios. **Sin esto solo tienes capacidad TEORICA** (de la auditoria
arquitectonica) — la unica forma de saber el techo real es golpear el sistema
hasta que se rompa en un entorno controlado.

---

## Instalacion de k6

Windows (con Chocolatey):
```powershell
choco install k6
```

Mac (con Homebrew):
```bash
brew install k6
```

Linux / otro: ver https://k6.io/docs/get-started/installation/.

Verificar:
```bash
k6 version
# k6 v0.50.0 (...)
```

---

## Tests disponibles

### `k6-baseline.js` — Aguante de la capa publica (sin auth)

Simula visitantes anonimos cargando home + assets + endpoints SEO. Rampa
escalonada 100 → 500 → 1000 → 2000 VUs concurrentes, 2 min en cada peldano.

**Que mide:**
- Aguante de Cloudflare CDN (cache hit ratio).
- Aguante del hosting Dondominio (para los misses).
- Latencia del bundle Flutter (5MB) bajo carga.

**No toca:** signup, login, IA, ninguna EF protegida. **No cuesta dinero**.

**Ejecutar:**
```bash
# Test completo (~10 min total)
k6 run tools/loadtest/k6-baseline.js

# Smoke rapido (30 seg, 50 VUs) para validar que el script funciona
k6 run --vus 50 --duration 30s tools/loadtest/k6-baseline.js

# Contra otro entorno
k6 run -e BASE_URL=https://staging.testexamen.es tools/loadtest/k6-baseline.js
```

---

## Cuando ejecutar

| Cuando | Por que |
|---|---|
| **Antes de marketing/lanzamiento masivo** | Validar techo real antes de que vengan users de verdad. |
| **Despues de cada gran sprint backend** | Detectar regresiones de capacidad (ej. M, N introdujeron RLS / cap / etc — ¿siguen aguantando?). |
| **Horario nocturno (3am UTC)** | Minimo impacto en users reales. |
| **Tras cambios de hosting / Cloudflare** | Confirma que la migracion mejoro (o al menos no degrado). |

---

## Como interpretar resultados

Al final del test k6 imprime un resumen tipo:

```
     ✓ home: status 200
     ✓ home: html valido
     ✓ asset: status 200 o 304

     checks.........................: 100.00% ✓ 8432   ✗ 0
     data_received..................: 4.2 GB  7.1 MB/s
     http_req_duration..............: avg=243ms  p(95)=1.1s  p(99)=2.3s
     http_req_failed................: 0.12%   ✓ 10     ✗ 8422
     iterations.....................: 4216    7.0/s
     vus............................: 1       min=1    max=2000
     vus_max........................: 2000
```

**Lectura recomendada:**

- `http_req_duration p(95) < 1s` → excelente, app rapida.
- `http_req_duration p(95) > 3s` → cuello de botella, mirar en que stage
  empezo a degradar.
- `http_req_failed > 5%` → app rompe a esa carga. **Tu techo real** es el
  numero de VUs del stage anterior.
- `data_received` total / 1024 → MB transferidos. Util para estimar coste
  de ancho de banda en pico.

**Donde mirar metricas correlacionadas durante el test:**

- **Cloudflare** → dashboard → Analytics → Traffic. Veras el RPS (requests/sec)
  y el % de cache hit. Cache hit > 80% es saludable.
- **Supabase** → dashboard → Database → Reports. Veras el % de conexiones
  ocupadas. > 80% sostenido = cuello de botella.
- **Sentry** (si pasa algo) → te llegaran emails si la app empieza a
  crashear bajo carga. Util para cazar bugs solo visibles en stress.

---

## Roadmap (tests futuros)

A medida que la app crece, anyadir:

- `k6-authed.js` — escenario con usuarios pre-creados (test_001@example.com
  ... test_500@example.com) haciendo login + abriendo panel + leyendo
  contenido. Mide aguante de la auth y RLS.

- `k6-generate.js` — solo para staging, simula generaciones de IA (cuesta
  dinero, tener cuidado). Mide el throughput de las EFs.

- `k6-signup.js` — signup masivo bypaseando captcha mediante un endpoint
  especial protegido por shared secret. Usa cap de signup test para no
  inundar la BD real.

---

## Costes esperados

Ejecutar `k6-baseline.js` UNA vez:
- ~4-8 GB de transferencia (en testexamen.es).
- Cloudflare absorbe el 80%+ (cache) → coste real al origen: 800MB-1.6GB.
- Supabase: muy poco (no se llama a EFs ni BD en este test).
- **Total estimado: < 1 EUR de transferencia** segun tu plan de hosting.

Hazlo de noche y no te entera nadie.
