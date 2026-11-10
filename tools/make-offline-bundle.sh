#!/bin/bash
# 講師用：產生教室離線 image 包（教室網路慢、或連不到 Docker Hub／mcr／nuget.org 時用）
# 在 devops-lab/ 根目錄下執行：bash tools/make-offline-bundle.sh [輸出目錄]
# 產出 keypasco-lab-images-amd64.tar（keypasco-lab-api＋postgres:16-alpine＋nginx:alpine），學員端：
#   docker load -i keypasco-lab-images-amd64.tar
# 注意：在 Apple Silicon 上會用模擬建置 amd64，較慢；做完本機的同名 image 會變成 amd64 版，
#       之後要在本機上課示範，重跑 docker build -t keypasco-lab-api apps/dotnet-deploylog 換回原生版。
set -euo pipefail

PLATFORM="${PLATFORM:-linux/amd64}"
OUT="${1:-.}"
NAME="keypasco-lab-images-${PLATFORM#linux/}.tar"
mkdir -p "$OUT"

echo "[1/3] 建置 keypasco-lab-api（${PLATFORM}）"
docker build --platform "$PLATFORM" -t keypasco-lab-api apps/dotnet-deploylog

echo "[2/3] 下載 mock 服務 image（${PLATFORM}）"
docker pull --platform "$PLATFORM" postgres:16-alpine
docker pull --platform "$PLATFORM" nginx:alpine

for img in keypasco-lab-api postgres:16-alpine nginx:alpine; do
  arch="$(docker image inspect -f '{{.Architecture}}' "$img")"
  if [ "$arch" != "${PLATFORM#linux/}" ]; then
    echo "$img 的架構是 ${arch}，不是 ${PLATFORM#linux/}——請確認 Docker 支援跨架構建置" >&2; exit 1
  fi
done

echo "[3/3] 匯出 $OUT/$NAME"
docker save -o "$OUT/$NAME" keypasco-lab-api postgres:16-alpine nginx:alpine
ls -lh "$OUT/$NAME"
echo "學員端：docker load -i $NAME"
