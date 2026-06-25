// ============================================================================
// k6 load test — baseline (paginas estaticas + assets)
// ----------------------------------------------------------------------------
// Mide el aguante de la capa publica (Cloudflare CDN + Apache hosting + bundle
// Flutter) sin tocar nada que cueste dinero (IA) ni nada protegido por captcha
// (signup). Es la SUITE BASE: si esto rompe a X concurrentes, sabes que todo
// lo demas tambien rompera.
//
// Escenario: rampa ascendente 100 -> 500 -> 1000 -> 2000 VUs (usuarios
// virtuales concurrentes), 2 min en cada peldano. Total: 8 min + ramp down.
// Cada VU simula a un visitante anonimo cargando la home y navegando.
//
// **Como ejecutar** (requiere k6 instalado: https://k6.io/docs/get-started/installation/):
//
//   k6 run tools/loadtest/k6-baseline.js
//
// **Para subir/bajar carga** sin editar el script:
//
//   k6 run --vus 50 --duration 30s tools/loadtest/k6-baseline.js   # smoke
//   k6 run -e BASE_URL=https://staging.testexamen.es tools/loadtest/k6-baseline.js
//
// **Cuando ejecutar:**
//   - Horario nocturno (3am UTC) para minimizar impacto a users reales.
//   - Despues de cada gran sprint para detectar regresiones de capacidad.
//   - Antes de marketing/lanzamiento masivo para validar techo.
//
// **Que medir** (k6 lo imprime al final):
//   - http_req_duration: latencia p50/p95/p99. p95 < 1s es saludable.
//   - http_req_failed: ratio de errores. Debe estar < 1% incluso en pico.
//   - vus_max: maximo de VUs alcanzado.
//   - iteration_duration: cuanto tarda un VU en completar el escenario.
//
// **Threshold automaticos**: el script falla con exit code != 0 si:
//   - >5% de requests dan error.
//   - p95 latencia > 3s.
//   Esto permite usar el script en CI para detectar regresiones.
// ============================================================================

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'https://testexamen.es';

// Metricas custom (visible en el reporte final).
const homeErrors = new Rate('home_errors');
const assetErrors = new Rate('asset_errors');
const homeLatency = new Trend('home_latency', true);

export const options = {
  // Rampa escalonada. En cada peldano nos quedamos 2 min para que las
  // metricas se estabilicen. Total: ~10 min de prueba.
  stages: [
    { duration: '30s', target: 100 },   // calentamiento
    { duration: '2m',  target: 100 },   // estable 100
    { duration: '30s', target: 500 },   // sube a 500
    { duration: '2m',  target: 500 },   // estable 500
    { duration: '30s', target: 1000 },  // sube a 1000
    { duration: '2m',  target: 1000 },  // estable 1000
    { duration: '30s', target: 2000 },  // sube a 2000
    { duration: '2m',  target: 2000 },  // estable 2000 (techo prueba)
    { duration: '30s', target: 0   },   // ramp down
  ],
  thresholds: {
    // Fallar el test si las metricas son malas - util en CI/automatic.
    http_req_failed:   ['rate<0.05'],   // <5% errores
    http_req_duration: ['p(95)<3000'],  // p95 < 3 segundos
    home_errors:       ['rate<0.05'],
    asset_errors:      ['rate<0.05'],
  },
  // Limitar tiempo total para no quemar el credito de k6 cloud si lo usan.
  // 10 min es suficiente.
  maxRedirects: 4,
  noConnectionReuse: false,  // reusa TCP (mas realista para CDN/HTTP2)
};

// Setup: corre 1 vez antes de la prueba. Imprime config para logs.
export function setup() {
  console.log(`Load test target: ${BASE_URL}`);
  console.log(`Total stages: ${options.stages.length}`);
  return { startTime: new Date().toISOString() };
}

// Cada VU corre esto en bucle hasta que termina su stage.
export default function () {
  group('home + assets', () => {
    // 1) Cargar la home. Si Cloudflare esta delante, el primer hit puede ir
    //    a origen, los siguientes salen de cache (mide cache hit ratio).
    const homeRes = http.get(`${BASE_URL}/`, {
      tags: { name: 'home' },
      headers: {
        // User-agent realista para que no nos filtre Cloudflare como bot.
        'User-Agent': 'Mozilla/5.0 (k6 load test) AppleWebKit/537.36 Chrome/132.0',
        'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
      },
    });
    homeLatency.add(homeRes.timings.duration);
    const homeOk = check(homeRes, {
      'home: status 200': (r) => r.status === 200,
      'home: html valido': (r) =>
        (r.body || '').includes('<html') || (r.body || '').includes('<!DOCTYPE'),
    });
    homeErrors.add(!homeOk);

    sleep(0.3);

    // 2) Descargar 2 assets representativos en paralelo (simula browser
    //    cargando bundle). Si Cloudflare cachea, deberian ser muy rapidos.
    const assetReqs = http.batch([
      ['GET', `${BASE_URL}/main.dart.js`, null, {
        tags: { name: 'main-bundle' },
      }],
      ['GET', `${BASE_URL}/flutter_bootstrap.js`, null, {
        tags: { name: 'flutter-bootstrap' },
      }],
    ]);
    for (const res of assetReqs) {
      const ok = check(res, {
        'asset: status 200 o 304': (r) => r.status === 200 || r.status === 304,
      });
      assetErrors.add(!ok);
    }

    sleep(0.5);

    // 3) Endpoints publicos sin auth (sitemap, robots) - lecturas baratas
    //    que el SEO crawler hace. Si estos se caen, ranking sufre.
    const robotsRes = http.get(`${BASE_URL}/robots.txt`, {
      tags: { name: 'robots' },
    });
    check(robotsRes, { 'robots: 200': (r) => r.status === 200 });

    // Pequenya pausa para no martillar como bot. Simula tiempo de lectura
    // del user real (1-3 seg entre acciones).
    sleep(1 + Math.random() * 2);
  });
}

// Teardown: corre 1 vez al final. Util para reporting o cleanup.
export function teardown(data) {
  console.log(`Test started: ${data.startTime}`);
  console.log(`Test ended:   ${new Date().toISOString()}`);
  console.log('Revisa Cloudflare Analytics + Supabase Dashboard para metricas en su lado.');
}
