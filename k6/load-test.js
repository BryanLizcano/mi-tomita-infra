/**
 * Prueba de desempeño — Tomita API
 * Uso: k6 run -e BASE_URL=http://ALB-DNS load-test.js
 * 
 * Instalar k6: https://k6.io/docs/get-started/installation/
 * En Windows: winget install k6 --source winget
 */
import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

// ── Métricas personalizadas ──────────────────
const errorsCount    = new Counter('errors_count');
const successRate    = new Rate('success_rate');
const responseTime   = new Trend('response_time_ms', true);
const hostnameCount  = {};  // para visualizar distribución del ALB

// ── Configuración de carga ───────────────────
export const options = {
  stages: [
    { duration: '30s', target: 10  },  // Calentamiento
    { duration: '1m',  target: 30  },  // Carga normal
    { duration: '1m',  target: 60  },  // Carga alta — forzar balanceo
    { duration: '30s', target: 100 },  // Pico de saturación
    { duration: '30s', target: 0   },  // Enfriamiento
  ],
  thresholds: {
    'http_req_duration':        ['p(95)<500', 'p(99)<1000'],
    'http_req_failed':          ['rate<0.05'],   // menos del 5% de errores
    'success_rate':             ['rate>0.95'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

// ── Escenario principal ──────────────────────
export default function () {
  group('Health Check', () => {
    const res = http.get(`${BASE_URL}/health`, {
      tags: { endpoint: 'health' },
    });

    const ok = check(res, {
      'health → 200':          (r) => r.status === 200,
      'health → tiene status': (r) => JSON.parse(r.body).status === 'ok',
      'health → tiempo < 300ms': (r) => r.timings.duration < 300,
    });

    successRate.add(ok);
    responseTime.add(res.timings.duration);

    if (!ok) errorsCount.add(1);

    // Registrar hostname para verificar distribución del ALB
    try {
      const body = JSON.parse(res.body);
      const host = body.hostname || 'unknown';
      hostnameCount[host] = (hostnameCount[host] || 0) + 1;
    } catch (_) {}
  });

  sleep(0.5);

  group('Status Check', () => {
    const res = http.get(`${BASE_URL}/status`, {
      tags: { endpoint: 'status' },
    });

    check(res, {
      'status → 200':            (r) => r.status === 200,
      'status → tiene uptime':   (r) => JSON.parse(r.body).uptime > 0,
    });

    responseTime.add(res.timings.duration);
  });

  sleep(0.5);

  group('API Test', () => {
    const res = http.get(`${BASE_URL}/api/test`, {
      tags: { endpoint: 'api-test' },
    });

    check(res, {
      'api/test → 200':    (r) => r.status === 200,
      'api/test → version': (r) => JSON.parse(r.body).version === '1.0.0',
    });
  });

  sleep(0.5);

  group('Productos', () => {
    const res = http.get(`${BASE_URL}/api/productos`, {
      tags: { endpoint: 'productos' },
    });

    check(res, {
      'productos → 200':       (r) => r.status === 200,
      'productos → tiene lista': (r) => {
        const body = JSON.parse(r.body);
        return Array.isArray(body.productos);
      },
    });
  });

  sleep(1);
}

// ── Resumen al finalizar ─────────────────────
export function handleSummary(data) {
  const p95 = data.metrics['http_req_duration']?.values?.['p(95)'] || 0;
  const p99 = data.metrics['http_req_duration']?.values?.['p(99)'] || 0;
  const errRate = (data.metrics['http_req_failed']?.values?.rate || 0) * 100;
  const reqs = data.metrics['http_reqs']?.values?.count || 0;

  const summary = `
╔══════════════════════════════════════════════════════╗
║         RESULTADOS — PRUEBA DE CARGA TOMITA API       ║
╠══════════════════════════════════════════════════════╣
║  Total requests:        ${String(reqs).padEnd(27)}║
║  p95 tiempo respuesta:  ${(p95.toFixed(1) + ' ms').padEnd(27)}║
║  p99 tiempo respuesta:  ${(p99.toFixed(1) + ' ms').padEnd(27)}║
║  Tasa de error:         ${(errRate.toFixed(2) + '%').padEnd(27)}║
╠══════════════════════════════════════════════════════╣
║  Distribución por instancia (ALB):                   ║
${Object.entries(hostnameCount).map(([h, c]) =>
  `║    ${h.slice(0, 20).padEnd(20)}: ${String(c).padEnd(4)} requests           ║`
).join('\n')}
╚══════════════════════════════════════════════════════╝
`;

  console.log(summary);

  return {
    stdout: summary,
    'k6-summary.json': JSON.stringify(data, null, 2),
  };
}
