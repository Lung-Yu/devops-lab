#!/bin/bash
# 課程環境自我測試（bash 版；Windows 用 selftest.ps1）
# 在 assets/ 目錄下執行：
#   bash tools/selftest.sh env                       # 只檢查環境（Docker、compose、對外連線、Port、磁碟）——開課前請教室先跑
#   bash tools/selftest.sh all                       # 環境＋M2 三組切換＋M4 五種破壞＋/health＋M6 網站（migrate、登入、權限）（講師課前驗收）
#   bash tools/selftest.sh m4 lab-m4-starter/start.sh  # 只對指定的預檢腳本跑五種破壞（檢核點 2 抽查學員腳本）
# 環境變數：LAB_PORT（預設 5000；Mac 的 5000 被 AirPlay 佔用時設 5050）
set -uo pipefail

MODE="${1:-all}"
SCRIPT="${2:-solutions/start.sh}"
LAB_PORT="${LAB_PORT:-5000}"
PASS=0; FAIL=0; WARN=0
TMP="$(mktemp -d)"
trap 'docker rm -f lab-api squatter > /dev/null 2>&1; rm -rf "$TMP"' EXIT

ok()   { echo "  [PASS] $*"; PASS=$((PASS + 1)); }
ng()   { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }
warn() { echo "  [WARN] $*"; WARN=$((WARN + 1)); }
section() { echo; echo "== $* =="; }

if [ ! -f docker-compose.yml ] || [ ! -d lab-project ]; then
  echo "請在 assets/ 目錄下執行（要看得到 docker-compose.yml 和 lab-project/）" >&2; exit 2
fi

check_env() {
  section "0. 環境"
  if docker version --format '{{.Server.Version}}' > /dev/null 2>&1; then ok "Docker 可用（server $(docker version --format '{{.Server.Version}}'))"; else ng "Docker 沒有在跑，或沒有權限（docker version 失敗）"; fi
  if docker compose version > /dev/null 2>&1; then ok "docker compose 可用"; else ng "沒有 docker compose"; fi
  for t in curl lsof pg_isready; do
    if command -v "$t" > /dev/null; then ok "有 $t"; else warn "沒有 ${t}（bash 版預檢會用到；Windows 學員做 PowerShell 版不需要）"; fi
  done
  for url in https://registry-1.docker.io/v2/ https://mcr.microsoft.com/v2/ https://api.nuget.org/v3/index.json https://registry.npmjs.org/ https://github.com; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$url")"
    if [ "$code" != "000" ]; then ok "連得到 ${url}（HTTP ${code}）"; else warn "連不到 ${url}（已預載 image／改發 tar 檔的話可以忽略）"; fi
  done
  for p in "$LAB_PORT" 5432 8081; do
    if lsof -iTCP:"$p" -sTCP:LISTEN > /dev/null 2>&1 && ! docker ps --format '{{.Ports}}' | grep -q ":$p->"; then
      ng "Port $p 被其他程式佔用（lsof -iTCP:$p -sTCP:LISTEN 查是誰）"
    else ok "Port $p 可用"; fi
  done
  free_gb="$(df -Pk . | awk 'NR==2 {print int($4/1024/1024)}')"
  if [ "$free_gb" -ge 5 ]; then ok "磁碟剩 ${free_gb} GB"; else warn "磁碟只剩 ${free_gb} GB（image 約需 3 GB）"; fi
  for img in keypasco-lab-api postgres:16-alpine nginx:alpine; do
    if docker image inspect "$img" > /dev/null 2>&1; then ok "image $img 已在本機"; else warn "image $img 還沒有（休息時要下載，或 docker load）"; fi
  done
}

wait_db() {
  for _ in $(seq 1 30); do
    [ "$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q mock-db)" 2>/dev/null)" = "healthy" ] && return 0
    sleep 1
  done
  return 1
}

start_deps() {
  section "1. 啟動 mock 服務"
  docker compose up -d mock-db mock-external-api > /dev/null 2>&1 || { ng "docker compose up 失敗"; return 1; }
  if wait_db; then ok "mock-db healthy"; else ng "mock-db 30 秒內沒有 healthy"; return 1; fi
  if curl -sf --max-time 3 http://localhost:8081/health > /dev/null; then ok "mock-external-api /health 200"; else ng "mock-external-api 沒有回應"; fi
  if ! docker image inspect keypasco-lab-api > /dev/null 2>&1; then
    echo "  建置 keypasco-lab-api（第一次要下載 base image）..."
    if docker build -q -t keypasco-lab-api lab-project > /dev/null; then ok "docker build 成功"; else ng "docker build 失敗"; return 1; fi
  else ok "image keypasco-lab-api 已存在"; fi
}

wait_http() {  # url 期望狀態碼 秒數
  for _ in $(seq 1 "$3"); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$1")" = "$2" ] && return 0
    sleep 1
  done
  return 1
}

test_m2() {
  section "2. Lab M2：三組 .env 不重新編譯切換"
  for pair in "dev:Development:labdb" "qa:QA:labdb_qa" "poc:POC:labdb_poc"; do
    IFS=: read -r e envname db <<< "$pair"
    docker rm -f lab-api > /dev/null 2>&1
    docker run -d --name lab-api -p "$LAB_PORT:5000" --env-file ".env.$e" keypasco-lab-api > /dev/null
    want="{\"environment\":\"$envname\",\"dbHost\":\"localhost\",\"dbName\":\"$db\"}"
    got=""
    for _ in $(seq 1 15); do got="$(curl -s --max-time 2 "http://localhost:$LAB_PORT/whoami")"; [ -n "$got" ] && break; sleep 1; done
    if [ "$got" = "$want" ]; then ok ".env.$e → $got"; else ng ".env.$e 預期 ${want}，實際 ${got:-（沒有回應）}"; fi
  done
  docker rm -f lab-api > /dev/null 2>&1
}

# 跑一次預檢腳本，檢查 exit code 和錯誤訊息關鍵字
expect_block() {  # 說明 env檔 關鍵字
  # 沒擋下的腳本會把服務跑在前景、不會結束：20 秒還沒結束就當成「服務啟動了」
  bash "$SCRIPT" "$2" > "$TMP/out" 2>&1 & pid=$!
  for _ in $(seq 1 20); do kill -0 "$pid" 2> /dev/null || break; sleep 1; done
  if kill -0 "$pid" 2> /dev/null; then
    docker rm -f lab-api > /dev/null 2>&1; kill "$pid" 2> /dev/null; wait "$pid" 2> /dev/null
    ng "$1 → 沒有擋下（服務直接啟動了）"; return
  fi
  wait "$pid"; code=$?; out="$(cat "$TMP/out")"
  if [ "$code" -ne 0 ] && grep -q "$3" <<< "$out"; then ok "$1 → exit ${code}，訊息含「$3」"
  elif [ "$code" -ne 0 ]; then warn "$1 → 有擋下（exit ${code}），但訊息沒有「$3」：$(tail -1 <<< "$out")"
  else ng "$1 → 沒有擋下（exit 0）"; fi
  docker rm -f lab-api > /dev/null 2>&1
}

test_m4() {
  section "3. Lab M4：預檢腳本 $SCRIPT"
  [ -f "$SCRIPT" ] || { ng "找不到 $SCRIPT"; return; }
  base="$TMP/env.base"; sed "s/^APP_PORT=.*/APP_PORT=$LAB_PORT/" .env.poc > "$base"

  grep -v '^DB_HOST=' "$base" > "$TMP/env.nohost"
  expect_block "#0 缺 DB_HOST" "$TMP/env.nohost" "DB_HOST"

  docker compose stop mock-external-api > /dev/null 2>&1
  expect_block "#1 外部服務停掉" "$base" "外部服務"
  docker compose start mock-external-api > /dev/null 2>&1; sleep 1

  docker run -d --name squatter -p "$LAB_PORT:80" nginx:alpine > /dev/null 2>&1; sleep 1
  expect_block "#2 Port $LAB_PORT 被佔用" "$base" "佔用"
  docker rm -f squatter > /dev/null 2>&1; sleep 1

  sed 's/^DB_HOST=.*/DB_HOST=localhsot/' "$base" > "$TMP/env.typo"
  expect_block "#3 DB_HOST 打錯" "$TMP/env.typo" "資料庫"

  docker compose stop mock-db > /dev/null 2>&1
  expect_block "#3 資料庫停掉" "$base" "資料庫"
  docker compose start mock-db > /dev/null 2>&1; wait_db

  section "4. 全部通過時啟動服務＋/health"
  bash "$SCRIPT" "$base" > "$TMP/run.log" 2>&1 &
  if wait_http "http://localhost:$LAB_PORT/health" 200 30; then ok "#4 四項預檢通過，服務啟動，/health 200"
  else ng "#4 服務沒有起來（$(tail -3 "$TMP/run.log" | tr '\n' ' ')）"; fi
  docker compose stop mock-db > /dev/null 2>&1
  if wait_http "http://localhost:$LAB_PORT/health" 503 15; then ok "#5 DB 停掉後 /health 503"; else ng "#5 DB 停掉後 /health 不是 503"; fi
  docker compose start mock-db > /dev/null 2>&1; wait_db
  if wait_http "http://localhost:$LAB_PORT/health" 200 20; then ok "DB 恢復後 /health 回到 200"; else ng "DB 恢復後 /health 沒有回到 200"; fi
  docker rm -f lab-api > /dev/null 2>&1; wait
}

# M6：migrate 前後 /health/ready、登入、三種角色的權限（後端擋，不是前端藏按鈕）
test_web() {
  section "5. M6 範例網站：migrate、登入、權限"
  local h=(--add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal) url="http://localhost:$LAB_PORT"
  docker compose exec -T mock-db psql -q -U labuser -d postgres -c "DROP DATABASE IF EXISTS labdb_poc WITH (FORCE)" -c "CREATE DATABASE labdb_poc" > /dev/null
  docker rm -f lab-api > /dev/null 2>&1
  docker run -d --name lab-api -p "$LAB_PORT:5000" --env-file .env.poc "${h[@]}" keypasco-lab-api > /dev/null
  if wait_http "$url/health/ready" 503 20; then ok "還沒 migrate：/health 200、/health/ready 503"; else ng "還沒 migrate 時 /health/ready 不是 503"; fi
  if docker run --rm --env-file .env.poc "${h[@]}" -e DB_NAME=labdb_typo keypasco-lab-api migrate > /dev/null 2>&1; then
    ng "DB_NAME 打錯時 migrate 沒有失敗"; else ok "DB_NAME 打錯：migrate exit 非 0，不會自己建新庫"; fi
  if docker run --rm --env-file .env.poc "${h[@]}" keypasco-lab-api migrate > /dev/null 2>&1; then ok "migrate 成功"; else ng "migrate 失敗"; fi
  if wait_http "$url/health/ready" 200 10; then ok "migrate 後 /health/ready 200"; else ng "migrate 後 /health/ready 不是 200"; fi
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$url/")" = 200 ] && ok "首頁（Vue 前端）200" || ng "首頁打不開"
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$url/api/deployments")" = 401 ] && ok "未登入讀資料 → 401" || ng "未登入讀資料不是 401"
  local body='{"customer":"selftest","environment":"QA","version":"0.0.1","status":"Planned","deployedAt":"2026-11-03T05:30:00Z"}'
  for pair in viewer:403 engineer:201; do
    IFS=: read -r u want <<< "$pair"
    curl -s -c "$TMP/c_$u" -H 'Content-Type: application/json' -d "{\"userName\":\"$u\",\"password\":\"Lab@2026\"}" "$url/api/auth/login" > /dev/null
    got="$(curl -s -o /dev/null -w '%{http_code}' -b "$TMP/c_$u" -H 'Content-Type: application/json' -d "$body" "$url/api/deployments")"
    [ "$got" = "$want" ] && ok "$u 新增部署紀錄 → $got" || ng "$u 新增部署紀錄預期 ${want}，實際 $got"
  done
  docker rm -f lab-api > /dev/null 2>&1
}

case "$MODE" in
  env) check_env ;;
  m4)  start_deps && test_m4 ;;
  all) check_env; start_deps && { test_m2; test_m4; test_web; } ;;
  *)   echo "用法：bash tools/selftest.sh [env|all|m4 <腳本>]" >&2; exit 2 ;;
esac

echo
echo "結果：PASS ${PASS}／WARN ${WARN}／FAIL $FAIL"
[ "$FAIL" -eq 0 ]
