#!/bin/bash
# 反面教材：直接啟動，什麼都不檢查
# （image 裡實際執行的就是 dotnet MyApi.dll）
# 用法（在 devops-lab/ 根目錄下）：bash labs/m4-preflight/starter/start-naive.sh
docker run --rm -p 5000:5000 --env-file .env.poc keypasco-lab-api
