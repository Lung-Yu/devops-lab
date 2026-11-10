#!/bin/bash
# 預檢啟動腳本（學員起始檔）：把四個 TODO 補完，任一項失敗就 exit 1
# 用法（在 devops-lab/ 根目錄下）：bash labs/m4-preflight/starter/start.sh .env.poc
set -euo pipefail   # 任一指令失敗就停、用到未定義變數就停

ENV_FILE="${1:-.env.poc}"
set -a; source "$ENV_FILE"; set +a   # 把 .env 裡的設定讀成環境變數

# TODO [0/3] 必填設定：EXTERNAL_API_URL、APP_PORT、DB_HOST、DB_PORT 少一個就停
#   提示：: "${DB_HOST:?缺少 DB_HOST，請檢查 $ENV_FILE}"

# TODO [1/3] 外部服務：curl -sf --max-time 3 "$EXTERNAL_API_URL/health" 失敗 → 印錯誤、exit 1

# TODO [2/3] Port：lsof -iTCP:"$APP_PORT" -sTCP:LISTEN 有結果 = 被佔用 → 印錯誤、exit 1

# TODO [3/3] 資料庫：pg_isready -h "$DB_HOST" -p "$DB_PORT" 失敗 → 印錯誤、exit 1

# 錯誤訊息三要素：哪裡錯、為什麼、去哪修（錯誤訊息印到 >&2）

echo "所有預檢通過，啟動服務..."
# 容器裡的 localhost 是容器自己，所以改用 host.docker.internal 連回這台電腦上的 mock-db
exec docker run --rm --name lab-api -p "$APP_PORT:5000" --env-file "$ENV_FILE" \
  --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal \
  keypasco-lab-api
