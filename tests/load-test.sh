#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
# Prueba de Carga — Apache Benchmark (ab) — Tomita API
# Alternativa a k6, incluida en Apache httpd-tools
# ═══════════════════════════════════════════════════════════════════════
# Instalar:  sudo yum install -y httpd-tools   (Amazon Linux)
#            sudo apt-get install -y apache2-utils  (Ubuntu/Debian)
#            choco install wget  (Windows - usar k6 mejor)
#
# Uso:   ./tests/load-test.sh http://tomita-alb-xxx.us-east-1.elb.amazonaws.com
# ═══════════════════════════════════════════════════════════════════════

set -e

ALB_URL="${1:-http://tomita-alb-1141831403.us-east-1.elb.amazonaws.com}"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
RESULTS_DIR="tests/resultados_${TIMESTAMP}"

mkdir -p "$RESULTS_DIR"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     PRUEBA DE CARGA — TOMITA S.A.S.  — $(date '+%H:%M:%S')         ║"
echo "║     Target: $ALB_URL"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Función de prueba ────────────────────────────────────────────────
run_test() {
  local endpoint="$1"
  local name="$2"
  local concurrency="$3"
  local requests="$4"
  local outfile="$RESULTS_DIR/${name}.txt"

  echo "▶ Probando: $name ($concurrency usuarios × $requests requests)"
  echo "  URL: $ALB_URL$endpoint"

  ab -n "$requests" \
     -c "$concurrency" \
     -H "Accept: application/json" \
     -s 30 \
     -r \
     "$ALB_URL$endpoint" > "$outfile" 2>&1

  # Extraer métricas clave
  local rps=$(grep "Requests per second" "$outfile" | awk '{print $4}')
  local avg=$(grep "Time per request.*mean\]" "$outfile" | head -1 | awk '{print $4}')
  local p95=$(grep "95%" "$outfile" | awk '{print $2}')
  local failed=$(grep "Failed requests" "$outfile" | awk '{print $3}')

  echo "  ✅ RPS: $rps | Promedio: ${avg}ms | P95: ${p95}ms | Fallos: $failed"
  echo ""
}

# ── Prueba 1: Health Check — carga baja ──────────────────────────────
run_test "/health" "health_low" 5 100

# ── Prueba 2: Health Check — carga media ─────────────────────────────
run_test "/health" "health_medium" 25 500

# ── Prueba 3: Health Check — carga alta (evidencia balanceador) ───────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "IMPORTANTE: Observar en esta prueba que 'hostname' varía entre"
echo "respuestas — esto DEMUESTRA que el ALB distribuye entre las 2 EC2"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_test "/health" "health_high_50vu" 50 1000

# ── Prueba 4: API Productos ───────────────────────────────────────────
run_test "/api/productos" "productos_medium" 20 300

# ── Evidencia de distribución del ALB ────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "EVIDENCIA DEL BALANCEADOR (10 requests consecutivos):"
echo "Observar que hostname alterna entre las instancias EC2:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for i in $(seq 1 10); do
  HOSTNAME=$(curl -s "$ALB_URL/health" | python3 -c "import sys,json; print(json.load(sys.stdin)['hostname'])" 2>/dev/null || \
             curl -s "$ALB_URL/health" | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)
  echo "  Request $i → hostname: $HOSTNAME"
  sleep 0.2
done
echo ""

# ── Resumen final ─────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  RESUMEN DE RESULTADOS                                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Archivos guardados en: $RESULTS_DIR/"
echo ""
echo "Métricas a relacionar con CloudWatch:"
echo "  1. ALB → TargetResponseTime  (vs tiempos medidos)"
echo "  2. ALB → RequestCount        (vs total requests enviados)"
echo "  3. EC2 → CPUUtilization      (debe subir durante la prueba)"
echo "  4. EC2 → mem_used_percent    (via CloudWatch Agent)"
echo ""
echo "URLs de CloudWatch relevantes:"
echo "  - Consola AWS → CloudWatch → Métricas → AWS/ApplicationELB"
echo "  - Consola AWS → CloudWatch → Métricas → AWS/EC2"
echo ""
echo "✅ Prueba de carga completada: $TIMESTAMP"
