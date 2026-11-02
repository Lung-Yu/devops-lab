#!/bin/bash
# 預檢啟動腳本（參考解答）：預檢全部通過，才啟動服務
# 用法（在 assets/ 目錄下）：bash solutions/start.sh .env.poc
set -euo pipefail   # 任一指令失敗就停、用到未定義變數就停

ENV_FILE="${1:-.env.poc}"
set -a; source "$ENV_FILE"; set +a   # 把 .env 裡的設定讀成環境變數

echo "[0/3] 檢查必填設定與工具"
: "${EXTERNAL_API_URL:?缺少 EXTERNAL_API_URL，請檢查 $ENV_FILE}"
: "${APP_PORT:?缺少 APP_PORT，請檢查 $ENV_FILE}"
: "${DB_HOST:?缺少 DB_HOST，請檢查 $ENV_FILE}"
: "${DB_PORT:?缺少 DB_PORT，請檢查 $ENV_FILE}"
for tool in curl lsof pg_isready docker; do
  if ! command -v "$tool" > /dev/null; then
    echo "❌ 這台電腦沒有 $tool 指令，預檢沒辦法做（請先安裝）" >&2; exit 1
  fi
done
echo "✅ 設定與工具齊全"

echo "[1/3] 檢查外部服務：$EXTERNAL_API_URL"
if ! curl -sf --max-time 3 "$EXTERNAL_API_URL/health" > /dev/null; then
  echo "❌ 無法連線到外部服務：$EXTERNAL_API_URL/health" >&2
  echo "   → 確認 mock-external-api 有在跑（docker compose ps），或檢查 $ENV_FILE 的 EXTERNAL_API_URL" >&2
  exit 1
fi
echo "✅ 外部服務正常"

echo "[2/3] 檢查 Port $APP_PORT 是否被佔用"
if lsof -iTCP:"$APP_PORT" -sTCP:LISTEN > /dev/null 2>&1; then
  echo "❌ Port $APP_PORT 已被佔用（用 lsof -iTCP:$APP_PORT -sTCP:LISTEN 查是誰）" >&2
  echo "   → 關掉佔用的程式（docker ps 看是不是舊容器），或改 $ENV_FILE 的 APP_PORT" >&2
  exit 1
fi
echo "✅ Port $APP_PORT 可用"

echo "[3/3] 檢查資料庫：$DB_HOST:$DB_PORT"
if ! pg_isready -h "$DB_HOST" -p "$DB_PORT" > /dev/null 2>&1; then
  echo "❌ 無法連線到資料庫：$DB_HOST:$DB_PORT" >&2
  echo "   → 確認 mock-db 有在跑（docker compose ps），或檢查 $ENV_FILE 的 DB_HOST / DB_PORT" >&2
  exit 1
fi
echo "✅ 資料庫連線正常"

echo "所有預檢通過，啟動服務..."
# 容器裡的 localhost 是容器自己，所以改用 host.docker.internal 連回這台電腦上的 mock-db
exec docker run --rm --name lab-api -p "$APP_PORT:5000" --env-file "$ENV_FILE" \
  --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal \
  keypasco-lab-api
