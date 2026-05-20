/**
 * Prueba de Carga — Tomita API
 * Herramienta: k6 (https://k6.io)
 *
 * Uso:
 *   k6 run tests/load-test.js
 *   k6 run --env ALB_URL=http://tomita-alb-xxx.us-east-1.elb.amazonaws.com tests/load-test.js
 *
 * Instalar k6 en Linux:
 *   sudo gpg -k
 *   sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
 *     --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
 *   echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] \
 *     https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
 *   sudo apt-get update && sudo apt-get install k6
 *
 * En Windows (PowerShell con Chocolatey):
 *   choco install k6
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// ── Métricas personalizadas ──────────────────────────────────────────────────
const errorRate       = new Rate('error_rate');
const healthDuration  = new Trend('health_duration',   true);
const apiDuration     = new Trend('api_duration',      true);
const totalRequests   = new Counter('total_requests');

// ── Configuración del target ─────────────────────────────────────────────────
const BASE_URL = __ENV.ALB_URL || 'http://tomita-alb-1141831403.us-east-1.elb.amazonaws.com';

// ── Escenarios de carga (prueba escalonada) ───────────────────────────────────
export const options = {
  scenarios: {
    // Fase 1: Carga gradual (rampa de subida)
    ramp_up: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 10 },   // Subir a 10 usuarios en 30s
        { duration: '1m',  target: 25 },   // Subir a 25 usuarios en 1min
        { duration: '1m',  target: 50 },   // Subir a 50 usuarios (carga alta)
        { duration: '30s', target: 0 },    // Bajar a 0 (rampa de bajada)
      ],
      gracefulRampDown: '10s',
    },
  },

  // ── Umbrales de aceptación ────────────────────────────────────────────────
  thresholds: {
    // 95% de requests deben responder en menos de 500ms
    'http_req_duration':  ['p(95)<500'],
    // Menos del 5% de errores permitidos
    'error_rate':         ['rate<0.05'],
    // El health endpoint siempre bajo 200ms
    'health_duration':    ['p(99)<200'],
  },
};

// ── Lógica principal de los usuarios virtuales ────────────────────────────────
export default function () {
  const headers = { 'Content-Type': 'application/json' };

  // ── Petición 1: Health check (valida que el ALB distribuye) ──────────────
  const healthRes = http.get(`${BASE_URL}/health`, { headers, tags: { endpoint: 'health' } });
  totalRequests.add(1);

  const healthOk = check(healthRes, {
    'health: status 200':          (r) => r.status === 200,
    'health: status = ok':         (r) => r.json('status') === 'ok',
    'health: tiene hostname':      (r) => r.json('hostname') !== null,
    'health: responde < 500ms':    (r) => r.timings.duration < 500,
  });

  healthDuration.add(healthRes.timings.duration);
  errorRate.add(!healthOk);

  sleep(0.5);

  // ── Petición 2: Endpoint de productos ────────────────────────────────────
  const prodRes = http.get(`${BASE_URL}/api/productos`, { headers, tags: { endpoint: 'productos' } });
  totalRequests.add(1);

  const prodOk = check(prodRes, {
    'productos: status 200':       (r) => r.status === 200,
    'productos: tiene array':      (r) => Array.isArray(r.json('productos')),
    'productos: no está vacío':    (r) => r.json('productos').length > 0,
    'productos: responde < 800ms': (r) => r.timings.duration < 800,
  });

  apiDuration.add(prodRes.timings.duration);
  errorRate.add(!prodOk);

  sleep(0.5);

  // ── Petición 3: API test ──────────────────────────────────────────────────
  const testRes = http.get(`${BASE_URL}/api/test`, { headers, tags: { endpoint: 'test' } });
  totalRequests.add(1);

  check(testRes, {
    'api/test: status 200':        (r) => r.status === 200,
    'api/test: versión 1.0.0':     (r) => r.json('version') === '1.0.0',
  });

  errorRate.add(testRes.status !== 200);

  // ── Petición 4 (ocasional): POST de producto nuevo ───────────────────────
  // Solo el 20% de los VUs hace escritura para simular tráfico realista
  if (Math.random() < 0.2) {
    const body = JSON.stringify({
      nombre: `Pintura Test VU-${__VU}`,
      precio: Math.floor(Math.random() * 5000) + 1000,
    });

    const postRes = http.post(`${BASE_URL}/api/productos`, body, {
      headers,
      tags: { endpoint: 'post_producto' },
    });
    totalRequests.add(1);

    check(postRes, {
      'POST producto: status 201': (r) => r.status === 201,
      'POST producto: tiene id':   (r) => r.json('id') !== null,
    });
    errorRate.add(postRes.status !== 201);
  }

  sleep(1);
}

// ── Resumen personalizado al finalizar ────────────────────────────────────────
export function handleSummary(data) {
  const summary = {
    timestamp: new Date().toISOString(),
    test_target: BASE_URL,
    results: {
      total_requests:     data.metrics.total_requests?.values?.count || 0,
      requests_per_sec:   data.metrics.http_reqs?.values?.rate?.toFixed(2) || 0,
      avg_duration_ms:    data.metrics.http_req_duration?.values?.avg?.toFixed(2) || 0,
      p95_duration_ms:    data.metrics.http_req_duration?.values['p(95)']?.toFixed(2) || 0,
      p99_duration_ms:    data.metrics.http_req_duration?.values['p(99)']?.toFixed(2) || 0,
      max_duration_ms:    data.metrics.http_req_duration?.values?.max?.toFixed(2) || 0,
      error_rate_percent: ((data.metrics.error_rate?.values?.rate || 0) * 100).toFixed(2),
      checks_passed:      data.metrics.checks?.values?.passes || 0,
      checks_failed:      data.metrics.checks?.values?.fails || 0,
    },
    load_balancer_evidence: '✅ Verificar en /health que hostname varía entre requests (distribución round-robin)',
    cloudwatch_metrics: [
      'AWS/ApplicationELB → RequestCount, TargetResponseTime, HTTPCode_Target_2XX_Count',
      'AWS/EC2 → CPUUtilization por instancia (app_1 y app_2)',
      'CWAgent → mem_used_percent, disk_used_percent',
      '/tomita/api → logs de aplicación',
    ],
  };

  console.log('\n========== RESUMEN PRUEBA DE CARGA TOMITA ==========');
  console.log(JSON.stringify(summary, null, 2));

  return {
    'tests/resultados-carga.json': JSON.stringify(summary, null, 2),
    stdout: `\nPrueba completada. Ver resultados en tests/resultados-carga.json\n`,
  };
}
