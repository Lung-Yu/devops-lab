# 指令速查＋自我檢測

> DevOps 實作課｜兩天課程的指令、檢查點、疑難排解一頁看完
> 所有指令都在 `assets/` 目錄下執行（解壓 `keypasco-devops-lab.zip` 後的那個資料夾）。課堂的網站 port 是 **5000**；Mac 的 5000 被 AirPlay 佔用時，`-p 5000:5000` 改 `-p 5050:5000`、網址改 5050。
> 指令兩邊一樣時只寫一次；不一樣時分 **bash**（macOS／Linux）和 **PowerShell**（Windows）兩欄。

---

## 一、指令速查

### 1. 環境：mock 服務（Docker Compose）

| 做什麼 | 指令（bash／PowerShell 相同） |
|-------|---------------------------|
| 進到課程資料夾 | `cd assets` |
| 啟動 mock DB 和 mock 外部服務 | `docker compose up -d mock-db mock-external-api` |
| 看狀態（mock-db 要 `(healthy)`） | `docker compose ps` |
| 模擬「資料庫連不上」 | `docker compose stop mock-db` |
| 恢復資料庫（等幾秒變 healthy） | `docker compose start mock-db` |
| 模擬「外部服務連不上」 | `docker compose stop mock-external-api` |
| 恢復外部服務 | `docker compose start mock-external-api` |
| 對資料庫下 SQL | `docker compose exec mock-db psql -U labuser -d <資料庫> -c "<SQL>"` |
| 檢查這台電腦的環境（Docker、Port、磁碟…） | bash：`bash tools/selftest.sh env`<br/>PowerShell：`powershell -ExecutionPolicy Bypass -File tools\selftest.ps1 env` |

三個環境的資料庫：Dev `labdb`、QA `labdb_qa`、POC `labdb_poc`（帳號 `labuser`）。

### 2. Image：建置或載入

| 做什麼 | 指令（相同） |
|-------|-----------|
| 建置（第一次要下載約 1.7 GB base image） | `docker build -t keypasco-lab-api lab-project` |
| 教室連不到網路時，從 USB 載入 | `docker load -i keypasco-lab-images-amd64.tar` |
| 確認 image 在 | `docker image ls keypasco-lab-api` |

### 3. 用 `.env` 跑網站（M2）

只看設定（`/whoami`，不連資料庫）：

```bash
docker run -d --name lab-api -p 5000:5000 --env-file .env.dev keypasco-lab-api
```

換環境：把 `.env.dev` 換成 `.env.qa`、`.env.poc`，**不用重新 build**。換之前先 `docker rm -f lab-api`。

要連資料庫（完整網站、M5、M6）時，多加兩個參數，讓容器連回這台電腦的 mock-db。先存成變數：

| bash | PowerShell |
|------|-----------|
| `H=(--add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal)` | `$H = @('--add-host=host.docker.internal:host-gateway', '-e', 'DB_HOST=host.docker.internal')` |

bash 欄的括號寫法 macOS 預設的 zsh 也能用；不要寫成 `H="…"` 再用 `$H`，zsh 不會把它拆成三個參數。

```bash
# bash／zsh
docker run -d --name lab-api -p 5000:5000 --env-file .env.poc "${H[@]}" keypasco-lab-api
```

```powershell
# PowerShell（注意是 @H）
docker run -d --name lab-api -p 5000:5000 --env-file .env.poc @H keypasco-lab-api
```

網站帳號 `admin`／`engineer`／`viewer`，密碼都是 `Lab@2026`（要先 migrate 才有，見第 7 組）。

### 4. 確認服務：`/whoami`、`/health`

| 做什麼 | bash | PowerShell |
|-------|------|-----------|
| 吃到哪組設定 | `curl http://localhost:5000/whoami` | `curl.exe http://localhost:5000/whoami` |
| 活著嗎（DB 連得上） | `curl -i http://localhost:5000/health` | `curl.exe -i http://localhost:5000/health` |
| 能接客嗎（＋Schema 版本） | `curl -i http://localhost:5000/health/ready` | `curl.exe -i http://localhost:5000/health/ready` |
| 用瀏覽器一次看三個 | http://localhost:5000/system | 同左 |

`/whoami` 的預期輸出：

```text
.env.dev  → {"environment":"Development","dbHost":"localhost","dbName":"labdb"}
.env.qa   → {"environment":"QA","dbHost":"localhost","dbName":"labdb_qa"}
.env.poc  → {"environment":"POC","dbHost":"localhost","dbName":"labdb_poc"}
```

`/health`：正常 `HTTP/1.1 200 OK` ＋ `Healthy`；DB 停掉 `HTTP/1.1 503 Service Unavailable` ＋ `Unhealthy`。

### 5. 預檢腳本（M4）

| | bash | PowerShell |
|---|------|-----------|
| 跑自己的腳本 | `bash lab-m4-starter/start.sh .env.poc` | `powershell -ExecutionPolicy Bypass -File lab-m4-starter\start.ps1 .env.poc` |
| 跑參考解答 | `bash solutions/start.sh .env.poc` | `powershell -ExecutionPolicy Bypass -File solutions\start.ps1 .env.poc` |
| 看上一個指令的 exit code | `echo $?` | `$LASTEXITCODE` |

全部通過時：

```text
[0/3] 檢查必填設定與工具
✅ 設定與工具齊全
[1/3] 檢查外部服務：http://localhost:8081
✅ 外部服務正常
[2/3] 檢查 Port 5000 是否被佔用
✅ Port 5000 可用
[3/3] 檢查資料庫：localhost:5432
✅ 資料庫連線正常
所有預檢通過，啟動服務...
```

服務在前景執行，`Ctrl+C` 停止。

**破壞與復原**（每次破壞後，exit code 要是 1）：

| 破壞 | 預期擋在 | 復原 |
|------|---------|------|
| 刪掉 `.env.poc` 的 `DB_HOST=` 那一行 | [0/3] | 加回 `DB_HOST=localhost` |
| `docker compose stop mock-external-api` | [1/3] | `docker compose start mock-external-api` |
| `docker run -d --name squatter -p 5000:80 nginx:alpine` | [2/3] | `docker rm -f squatter` |
| `.env.poc` 的 `DB_HOST` 改成 `localhsot` | [3/3] | 改回 `localhost` |
| `docker compose stop mock-db` | [3/3] | `docker compose start mock-db` |

### 6. Log（M5）

| 做什麼 | bash | PowerShell |
|-------|------|-----------|
| 全部 log | `docker logs lab-api` | 同左 |
| 最後 30 行 | `docker logs --tail 30 lab-api` | 同左 |
| 持續看新的（`Ctrl+C` 離開） | `docker logs -f lab-api` | 同左 |
| 最近 10 分鐘 | `docker logs --since 10m lab-api` | 同左 |
| 用追蹤編號找 | `docker logs lab-api 2>&1 \| grep <追蹤編號>` | `docker logs lab-api 2>&1 \| Select-String <追蹤編號>` |
| 容器是不是掛了（含已停止的） | `docker ps -a --filter name=lab-api` | 同左 |
| PowerShell 中文亂碼時 | — | `[Console]::OutputEncoding = [Text.Encoding]::UTF8` |
<!-- 未驗證：PowerShell 尚未在 Windows 實測（Select-String 查 log、OutputEncoding 修正） -->

Log 格式：Development 是純文字（一筆拆成好幾行，不能用 JSON 工具查）；QA、POC 是一行一筆 JSON（有 `TraceId` 欄位）。POC 只輸出 Warning 以上。

### 7. Migrate（M6）

先照第 3 組設好 `H` 變數（bash 指令裡寫成 `"${H[@]}"`，PowerShell 寫成 `@H`）。

| 做什麼 | bash | PowerShell |
|-------|------|-----------|
| 升級 Schema | `docker run --rm --env-file .env.poc "${H[@]}" keypasco-lab-api migrate` | `docker run --rm --env-file .env.poc @H keypasco-lab-api migrate` |
| 把某個環境的 DB 清成空的 | `docker compose exec mock-db psql -U labuser -d postgres -c "DROP DATABASE IF EXISTS labdb_poc WITH (FORCE)" -c "CREATE DATABASE labdb_poc"` | 同左 |
| 查 DB 目前的 Schema 版本 | `docker compose exec mock-db psql -U labuser -d labdb_poc -c 'SELECT * FROM "__EFMigrationsHistory"'` | `'SELECT * FROM "__EFMigrationsHistory";' \| docker compose exec -T mock-db psql -U labuser -d labdb_poc` |
<!-- 未驗證：PowerShell 尚未在 Windows 實測（用管線送 SQL 給 psql 的寫法；bash 欄已實測） -->

換環境：`.env.poc` 換成 `.env.qa`／`.env.dev`，`labdb_poc` 換成 `labdb_qa`／`labdb`。**網站和 migrate 要用同一份 `.env`。**

migrate 的預期訊息（每行一筆 JSON，看 `Message`）：第一次「已套用 0 個，待套用 2 個 …」→「已建立預設帳號 …」→「Migration 完成，目前版本 20261027161130_AddAuditLogs」；再跑一次「已套用 2 個，待套用 0 個」→「Migration 完成 …」。`DB_NAME` 打錯時「找不到資料庫 …」，exit code 1。

### 8. 收尾

| 做什麼 | 指令（相同） |
|-------|-----------|
| 刪掉網站容器 | `docker rm -f lab-api` |
| 刪掉佔 port 的練習容器 | `docker rm -f squatter` |
| 停掉 mock 服務（資料保留） | `docker compose stop` |
| 停掉並刪除（下次重新建資料庫） | `docker compose down -v` |

### 9. Java 組：spring-demo（09）

先照第 3 組設好 `H`。

| 做什麼 | bash | PowerShell |
|-------|------|-----------|
| 建 image | `docker build -t deploylog-spring spring-demo` | 同左 |
| 用 POC 設定啟動（port 8080） | `docker run -d --name spring-api -p 8080:8080 --env-file .env.poc -e SPRING_PROFILES_ACTIVE=poc "${H[@]}" deploylog-spring` | `docker run -d --name spring-api -p 8080:8080 --env-file .env.poc -e SPRING_PROFILES_ACTIVE=poc @H deploylog-spring` |
| liveness／readiness | `curl localhost:8080/actuator/health/liveness`（readiness 同理） | `curl.exe localhost:8080/actuator/health/liveness` |
| 關掉自動 migrate | 啟動時加 `-e SPRING_FLYWAY_ENABLED=false` | 同左 |
| 查 Flyway 版本表 | `docker compose exec mock-db psql -U labuser -d labdb_poc -c "SELECT version, description, success FROM spring_demo.flyway_schema_history"` | 同左 |
| 刪掉容器 | `docker rm -f spring-api` | 同左 |

換環境：`.env.poc`／`poc` 換成 `.env.qa`／`qa` 或 `.env.dev`／`dev`。Flyway CLI 單獨 migrate 的完整指令見 [09 步驟 7](09-java-spring-demo.md#步驟-7正式環境把-migrate-拆出來m6)。

---

## 二、自我檢測

兩天各有一個實作檢核點。照下面的清單自己（或兩人一組互相）驗一次；每一項都有「怎麼驗」。

### Day 1：M2 組態切換

**情境**：同一份程式，不改程式碼、不重新編譯，只靠外部設定在 Dev／QA／POC 三個環境間切換。

| # | 檢核項目 | 怎麼驗 | ✓ |
|---|---------|-------|:---:|
| 1 | 用 `.env.dev` 啟動，`/whoami` 回 `"environment":"Development"`、`"dbName":"labdb"` | 指令速查第 3、4 組 | ☐ |
| 2 | 換成 `.env.qa`，不重新編譯，回 `"environment":"QA"`、`"dbName":"labdb_qa"` | 先 `docker rm -f lab-api`，只換 `--env-file` | ☐ |
| 3 | 換成 `.env.poc`，不重新編譯，回 `"environment":"POC"`、`"dbName":"labdb_poc"` | 同上 | ☐ |
| 4 | 能說出 `appsettings.json`／`appsettings.{Env}.json`／環境變數三層各放什麼 | 說給組員聽 | ☐ |
| 5 | 能指出連線字串、API Key 應該放在哪一層，以及為什麼不進版控 | 說給組員聽 | ☐ |

詳細步驟：[02-m2-config.md](02-m2-config.md)

### Day 2：M4 預檢啟動腳本

**情境**：組內互相破壞一項條件（拿掉必填變數／改錯 `DB_HOST`／佔用 Port／停掉外部服務或資料庫），確認腳本能友善報錯並阻斷啟動。一人破壞、一人看腳本反應，再互換。Shell 或 PowerShell 任選一版。

| # | 檢核項目 | 怎麼驗 | ✓ |
|---|---------|-------|:---:|
| 0 | 必填環境變數（如 `DB_HOST`）缺少時，印出清楚錯誤訊息並阻斷啟動（exit 1） | 破壞表第 1 列 | ☐ |
| 1 | 外部服務連不到時，印出清楚錯誤訊息並阻斷啟動 | 破壞表第 2 列 | ☐ |
| 2 | Port 被佔用時，印出清楚錯誤訊息並阻斷啟動 | 破壞表第 3 列 | ☐ |
| 3 | 資料庫連不上時，印出清楚錯誤訊息並阻斷啟動 | 破壞表第 4、5 列 | ☐ |
| 4 | 四項預檢都通過時，服務正常啟動 | 全部復原後再跑一次 | ☐ |
| 5 | （開發職務）`/health` 在資料庫斷線時回報 `Unhealthy` | 服務跑著時 `docker compose stop mock-db`，打 `/health` 看到 503 | ☐ |

「清楚的錯誤訊息」用三要素判斷：**哪裡錯、為什麼、去哪修**。例如：

```text
❌ 無法連線到資料庫：localhost:5432
   → 確認 mock-db 有在跑（docker compose ps），或檢查 .env.poc 的 DB_HOST / DB_PORT
```

詳細步驟：[04-m4-deploy-scripts.md](04-m4-deploy-scripts.md)

### 延伸：M5、M6 做得到嗎

| 檢核項目 | 詳細步驟 | ✓ |
|---------|---------|:---:|
| 從錯誤畫面的追蹤編號，在 `docker logs` 找到那一行，說出根因 | [05-m5-logging.md](05-m5-logging.md) 實作 | ☐ |
| 空資料庫時 `/health/ready` 是 503；migrate 後變 200；能查出 DB 的 Schema 版本 | [06-m6-db-migration.md](06-m6-db-migration.md) Lab | ☐ |

---

## 三、疑難排解（兩天合併）

### 環境與 Docker

| 症狀 | 原因 | 處理 |
|------|------|------|
| `docker` 指令找不到／無法連線 | Docker Desktop 沒開 | 開 Docker Desktop，等鯨魚圖示穩定 |
| mock-db 一直不是 healthy | 第一次啟動在建資料庫 | 等 10–20 秒再 `docker compose ps` |
| `docker build` 卡在下載或 restore 失敗 | 教室網路連不到 Docker Hub／mcr／nuget.org | 用 USB 的 tar：`docker load -i keypasco-lab-images-amd64.tar` |
| Day 2 開機後 image 不見了 | 教室電腦有還原卡 | `docker load -i keypasco-lab-images-amd64.tar` |
| `port is already allocated` | 上一輪容器沒刪 | `docker rm -f lab-api`（或 `squatter`）；Mac 是 AirPlay 佔 5000 → 改 5050 |
| `Conflict. The container name "/lab-api" is already in use` | 同名容器還在 | `docker rm -f lab-api` |

### M2 設定

| 症狀 | 原因 | 處理 |
|------|------|------|
| `curl` 輸出一大串表格 | Windows PowerShell 的 `curl` 是 `Invoke-WebRequest` | 打 `curl.exe`，或用瀏覽器開 |
| `/whoami` 的 environment 對、但 dbName 不對 | `ASPNETCORE_ENVIRONMENT` 和 json 檔名大小寫不一致 | 檔名 `appsettings.QA.json` ↔ `QA` 一字不差 |
| `.env` 裡寫 `$DB_HOST` 沒被展開 | `docker run --env-file` 不展開變數 | 每個值直接寫死在 `.env` 裡 |

### M4 預檢腳本

| 症狀 | 原因 | 處理 |
|------|------|------|
| `.ps1 cannot be loaded … execution policy` | Windows 執行原則 | `powershell -ExecutionPolicy Bypass -File ...` |
| `.ps1` 中文亂碼 | 用記事本另存成沒有 BOM 的 UTF-8 | 另存「UTF-8 (BOM)」 |
| 主控台把 ✅／❌ 顯示成 `?` | 主控台字型 | 不影響判斷結果 |
| `bash` 版說沒有 `lsof`／`pg_isready` | Git Bash 沒有這些工具 | Windows 學員做 PowerShell 版 |
| PowerShell 說 `Get-NetTCPConnection` not recognized | 那是 Windows 專用指令，Linux 的 PowerShell 沒有 | 用參考解答裡的 .NET 寫法 |
| 預檢全過，但 `/health` 是 Unhealthy | 啟動那行少了 `-e DB_HOST=host.docker.internal` | 容器裡的 localhost 是容器自己；對照起始檔最後一行 |
| Mac 上 [2/3] 一直擋 Port 5000 | AirPlay 佔用 | `.env.poc` 的 `APP_PORT` 改 5050（被擋是正確行為） |

### M5 Log

| 症狀 | 原因 | 處理 |
|------|------|------|
| 畫面有追蹤編號，log 搜不到 | 編號不完整（要 32 碼）／容器刪掉重建過（舊 log 跟著舊容器不見） | 重新複製；確認是同一個容器 |
| PowerShell 裡 log 的中文亂碼 | 主控台編碼 | `[Console]::OutputEncoding = [Text.Encoding]::UTF8` |
| POC 的 log 幾乎是空的 | POC 只輸出 Warning 以上 | 正常行為 |
| 容器跑一下就不見 | 啟動失敗 | `docker ps -a` 看 STATUS；`docker logs lab-api` 看最後幾行 |

### M6 Migrate 與網站

| 症狀 | 原因 | 處理 |
|------|------|------|
| 登入畫面「資料庫 Schema 不是最新版」 | 這個環境還沒 migrate | 指令速查第 7 組 |
| 登入畫面「資料庫連不上」 | 少了 `"${H[@]}"`／`@H`，或 mock-db 停了 | 補參數；`docker compose ps` |
| 登入畫面「找不到資料庫」／migrate 說找不到資料庫 | `DB_NAME` 打錯 | 檢查 `.env` |
| migrate 成功但 `/health/ready` 還是 503 | 網站和 migrate 用了不同的 `.env` | 用同一份 `--env-file` |
| PowerShell 報 `invalid reference format` | 沒設 `$H`，或指令裡寫 `$H` 而不是 `@H` | 重設 `$H`，指令用 `@H` |
| Mac 報 `invalid argument "host.docker.internal:host-gateway -e …" for "--add-host" flag` | `H` 用了引號字串，zsh 不會拆開 | 用括號 `H=(…)`，指令寫 `"${H[@]}"`（指令速查第 3 組） |
| psql 報 `relation "__efmigrationshistory" does not exist` | 表名的雙引號被 shell 吃掉 | 用管線寫法（指令速查第 7 組的 PowerShell 欄） |

### GitLab 示範（M3）

| 症狀 | 原因 | 處理 |
|------|------|------|
| deploy job 紅燈，log 最後是「60 秒內沒有 ready」 | 網站起不來（看 log 下面印的容器 log） | 通常是 DB 沒起來 |
| Rollback 按鈕是灰的 | 只有一筆部署 | 至少要兩筆部署才能退 |

更多見 [03b-gitlab-environments-release.md](03b-gitlab-environments-release.md) 第 10 節。

---

## 四、課程總結：帶走的觀念

### 六個模組總回顧

| 模組 | 帶走的觀念 |
|------|-----------|
| M1 可維運性思維 | Config 分離／Immutable Artifact（同一個 image 跑到底）／Design for Operations |
| M2 組態管理 | appsettings 三層分工，機密不進版控 |
| M3 CI Pipeline | 自動化取代手動記憶，雙語言同一套邏輯，版本可追溯 |
| M4 預檢機制 | 任一項失敗就阻斷，不讓服務帶病上線；`/health` 隨時回報 |
| M5 日誌與排查 | 分級／結構化／Trace ID |
| M6 DB Schema 管理 | Schema 版控，跟組態管理同一個精神 |

貫穿六個模組的一句話：**不靠人記得，交給版控和流程。**

```mermaid
flowchart LR
  M1["M1 想清楚<br/>要交付什麼"] --> M2["M2 設定<br/>抽出程式碼"] --> M3["M3 CI 自動建置<br/>版本可追溯"] --> M6["M6 部署前<br/>先 migrate"] --> M4["M4 預檢<br/>＋ /health/ready"] --> M5["M5 出事時<br/>log 找得到"]
```

### 回去挑一件事做

依你的職務，至少挑一項：

| # | 行動 | 建議誰做 |
|---|------|---------|
| 1 | 檢查連線字串、API Key 有沒有寫死在程式碼或版控裡 | 開發 |
| 2 | 部署腳本加上預檢：必填變數／網路／Port／DB | 維運 |
| 3 | 找一支正式服務補上 `/health`，監控看狀態碼 | 全部 |
| 4 | Log 分級健檢：Error 是不是都能讓人採取行動？ | QA |
| 5 | 下一次 Schema 變更寫成 migration，查得到 DB 版本 | 開發 |

開發可以從 1／3／5 挑，維運從 2／3，QA 從 3／4。

> **你寫的程式碼，決定了未來有沒有人半夜被叫醒。**

各模組的完整步驟：[README.md](README.md)
