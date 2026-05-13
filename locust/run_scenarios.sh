#!/usr/bin/env bash
# run_scenarios.sh

LOCUST_URL="http://localhost:8089"
OUT_DIR="scenario_results"
CSV="${OUT_DIR}/summary.csv"
DURATION=60
SPAWN_RATE=5

mkdir -p "$OUT_DIR"

# Ajuste o IP abaixo se necessário.
# Para descobrir: docker network inspect bridge --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}'
GATEWAY="172.17.0.1"

declare -A SERVICES=(
  ["ruby_com_cache"]="http://${GATEWAY}:4567"
  ["ruby_sem_cache"]="http://${GATEWAY}:4566"
  ["python_com_cache"]="http://${GATEWAY}:5000"
  ["python_sem_cache"]="http://${GATEWAY}:4999"
)

VU_COUNTS=(1 5 10 25 50)

echo "scenario,service,cache,users,total_requests,failures,failure_rate_pct,avg_ms,median_ms,p75_ms,p90_ms,p95_ms,p99_ms,min_ms,max_ms,rps,timestamp" > "$CSV"
echo "==> Resultados em: $CSV"
echo ""

# Retorna o estado atual do Locust (stopped/running/spawning)
locust_state() {
  curl -s --max-time 5 "${LOCUST_URL}/stats/requests" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('state','unknown'))" 2>/dev/null \
    || echo "unreachable"
}

# Aguarda Locust ficar parado (até 40s)
wait_stopped() {
  local i=0
  while [[ $i -lt 20 ]]; do
    local state; state=$(locust_state)
    if [[ "$state" == "stopped" || "$state" == "ready" ]]; then
      return 0
    fi
    sleep 2
    (( i++ )) || true
  done
  echo "    AVISO: Locust não parou no tempo esperado (state=$(locust_state))"
}

# Coleta as métricas do endpoint /stats/requests e adiciona linha ao CSV
collect() {
  local label="$1" service="$2" cache="$3" users="$4"

  local raw
  raw=$(curl -s --max-time 10 "${LOCUST_URL}/stats/requests")

  if [[ -z "$raw" ]]; then
    echo "    ERRO: resposta vazia do Locust ao coletar métricas"
    return 1
  fi

  echo "$raw" | python3 << PYEOF
import sys, json

try:
    data = json.loads("""${raw}""")
except Exception as e:
    print(f"ERRO ao parsear JSON: {e}", file=sys.stderr)
    sys.exit(1)

agg = next((s for s in data.get("stats", []) if s.get("name") == "Aggregated"), None)
if not agg:
    print("AVISO: sem entrada Aggregated", file=sys.stderr)
    sys.exit(0)

total    = agg.get("num_requests", 0)
failures = agg.get("num_failures", 0)
fail_pct = round(failures / total * 100, 4) if total else 0.0

samples = []
for ms, cnt in agg.get("response_times", {}).items():
    samples.extend([float(ms)] * int(cnt))
samples.sort()

def pct(lst, p):
    if not lst: return 0.0
    return round(lst[min(int(len(lst) * p / 100), len(lst)-1)], 2)

from datetime import datetime, timezone
ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

row = [
    "${label}", "${service}", "${cache}", "${users}",
    total, failures, fail_pct,
    round(agg.get("avg_response_time", 0), 2),
    round(agg.get("median_response_time", 0), 2),
    pct(samples, 75), pct(samples, 90),
    pct(samples, 95), pct(samples, 99),
    round(agg.get("min_response_time") or 0, 2),
    round(agg.get("max_response_time") or 0, 2),
    round(agg.get("current_rps", 0), 2),
    ts,
]
print(",".join(str(x) for x in row))
PYEOF
}

run() {
  local label="$1" host="$2" users="$3"
  local service cache
  [[ "$label" == ruby*   ]] && service="ruby"      || service="python"
  [[ "$label" == *com*   ]] && cache="com_cache"   || cache="sem_cache"

  echo ">>> ${label} | users=${users} | host=${host}"

  # Para qualquer teste em andamento
  curl -s "${LOCUST_URL}/stop" -o /dev/null || true
  sleep 1

  # Reseta estatísticas
  curl -s "${LOCUST_URL}/stats/reset" -o /dev/null || true
  sleep 1

  # Inicia o teste
  local resp
  resp=$(curl -s -X POST "${LOCUST_URL}/swarm" \
    -d "user_count=${users}&spawn_rate=${SPAWN_RATE}&host=${host}")
  echo "    swarm: $resp"

  echo "    Aguardando ${DURATION}s..."
  sleep "$DURATION"

  # Para o teste
  curl -s "${LOCUST_URL}/stop" -o /dev/null || true
  echo "    Parando... aguardando estabilizar"
  sleep 3

  # Coleta e salva
  local line
  line=$(collect "$label" "$service" "$cache" "$users")
  if [[ -n "$line" ]]; then
    echo "$line" >> "$CSV"
    echo "    OK: $line"
  fi

  echo ""
  wait_stopped
}

# Verifica se o Locust está acessível
echo "Verificando conexão com Locust em ${LOCUST_URL}..."
state=$(locust_state)
if [[ "$state" == "unreachable" ]]; then
  echo "ERRO: Locust não está acessível em ${LOCUST_URL}"
  echo "Rode: docker compose up -d"
  exit 1
fi
echo "Locust OK (state=${state})"
echo ""

for users in "${VU_COUNTS[@]}"; do
  for label in "${!SERVICES[@]}"; do
    run "$label" "${SERVICES[$label]}" "$users"
  done
done

echo "==> Concluído! CSV: ${CSV}"
echo "==> Rode agora: python3 build_report.py"
