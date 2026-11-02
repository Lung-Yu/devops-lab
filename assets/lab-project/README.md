# DeployLog 部署紀錄系統（課程範例專案）

記錄「哪個客戶環境、裝了哪個版本、結果如何」的內部網站。功能刻意做小，但一般網站會有的零件都有：前端畫面、後端 API、登入、角色權限、資料庫、Schema 版本管理、健康檢查、結構化日誌。課程六個模組都拿它當示範對象。

## 架構

```
瀏覽器 ──► 一個容器（keypasco-lab-api）───────────────► PostgreSQL（mock-db）
            ├─ wwwroot/        Vue3 前端（建置後的靜態檔）
            ├─ /api/*          ASP.NET Core 10 Minimal API
            ├─ /health         DB 連得上嗎（M4）
            ├─ /health/ready   DB 連得上＋Schema 是最新版（M6）
            └─ /whoami         吃到哪組設定（M2）
```

前端跟後端打包成**同一個 image**（`Dockerfile` 三階段：node 建前端 → SDK 編後端 → aspnet 執行），同一個網址，不需要 CORS。這個 image 從 Dev 到 POC 都是同一顆，換環境只換設定（M1 不可變交付物、M2 組態解耦）。

## 目錄

| 路徑 | 內容 | 對應模組 |
|------|------|---------|
| `Program.cs` | 設定、登入、權限規則、健康檢查、錯誤格式、路由——整個服務怎麼組起來的一頁看完 | M2、M4、M5 |
| `appsettings*.json` | 分層設定：共用 → 各環境覆寫；機密不放這裡 | M2 |
| `Data/Entities.cs` | 資料表：User、Deployment、AuditLog；三種角色 | M6 |
| `Data/DbSetup.cs` | `migrate` 指令：套用 Migration＋建課堂預設帳號 | M6 |
| `Migrations/` | EF Core 產生的 Schema 版本檔：`InitialCreate` → `AddAuditLogs` | M6 |
| `Endpoints/` | API：登入、部署紀錄、帳號管理、稽核紀錄 | — |
| `Infrastructure/` | Schema 健康檢查、資料庫錯誤轉成看得懂的訊息、稽核紀錄 | M4、M5、M6 |
| `RequiredSettings.cs` | 必填設定檢查（CI 單元測試的對象） | M3 |
| `frontend/` | Vue3＋Vite 原始碼；`package-lock.json` 鎖版本 | M3 |
| `Dockerfile` | 三階段建置；`--locked-mode`／`npm ci` 依 lock file 還原 | M1、M3 |

## 角色與權限

| 功能 | Viewer 檢視者 | Engineer 工程師 | Admin 管理員 |
|------|:---:|:---:|:---:|
| 看部署紀錄、系統狀態 | ✓ | ✓ | ✓ |
| 登錄／修改部署紀錄 | — | ✓ | ✓ |
| 刪除部署紀錄 | — | — | ✓ |
| 帳號管理、稽核紀錄 | — | — | ✓ |

- **後端把關**：規則寫在 `Program.cs` 的 `AddAuthorizationBuilder()`（`CanEdit`、`AdminOnly`），端點用 `.RequireAuthorization("CanEdit")` 套用。前端藏按鈕只是方便，直接打 API 一樣會被擋：未登入 401、權限不足 403。
- **Cookie 登入**：HttpOnly（JavaScript 讀不到）、SameSite=Strict（擋跨站請求偽造）。每個請求都回資料庫確認帳號狀態，停用或改角色立即生效。
- **密碼**只存 PBKDF2 雜湊（`PasswordHasher`）；登入失敗不分「帳號不存在」或「密碼錯」，避免被拿來猜帳號；失敗紀錄寫進稽核紀錄，但不記密碼。
- 管理員不能降低自己的權限或停用自己（避免系統裡沒有管理員）。

課堂預設帳號 `admin`／`engineer`／`viewer`，密碼都是 `Lab@2026`（`migrate` 時建立，可用 `SEED_PASSWORD` 環境變數改）。**正式系統不要有預設密碼。**

## 跑起來

在 `assets/` 目錄下：

```bash
docker compose up -d mock-db                        # PostgreSQL
docker build -t keypasco-lab-api lab-project        # 第一次約 1–3 分鐘（要下載 node、.NET image 與套件）

# 1. 先建資料表（Schema 變更是獨立的一步，不在服務啟動時偷偷做）
docker run --rm --env-file .env.dev --add-host=host.docker.internal:host-gateway \
  -e DB_HOST=host.docker.internal keypasco-lab-api migrate

# 2. 再啟動網站
docker run -d --name lab-api -p 5000:5000 --env-file .env.dev --add-host=host.docker.internal:host-gateway \
  -e DB_HOST=host.docker.internal keypasco-lab-api
# 瀏覽器開 http://localhost:5000
```

為什麼要 `-e DB_HOST=host.docker.internal`：`.env` 的 `DB_HOST=localhost` 是給在你電腦上跑的預檢腳本用的；容器裡的 `localhost` 是容器自己，要用 `host.docker.internal` 才連得回你的電腦（M4 Lab 有完整說明）。

Mac 的 5000 被 AirPlay 佔用時，`-p 5050:5000`、網址改 5050。

## 會看到的錯誤（都是故意設計的教材）

| 情況 | 畫面／API | `/health` | `/health/ready` |
|------|----------|:---:|:---:|
| 正常 | — | 200 | 200 |
| 還沒跑 `migrate` | 「資料庫 Schema 不是最新版」＋追蹤編號 | 200 | **503** |
| mock-db 停掉 | 「資料庫連不上」＋追蹤編號 | **503** | **503** |
| `DB_NAME` 打錯 | 「找不到資料庫」 | **503** | **503** |
| `migrate` 時 `DB_NAME` 打錯 | 失敗、exit 1，**不會**自己建一個新的空資料庫 | — | — |

錯誤訊息裡的**追蹤編號**也在回應標頭 `X-Trace-Id` 和伺服器 log 裡（`docker logs lab-api | grep <編號>`）——使用者回報編號，維運直接找到那一筆（M5）。

## 開發時（選讀，需要 .NET 10 SDK 與 Node 22）

```bash
dotnet run                                  # 後端 http://localhost:5000（ASPNETCORE_ENVIRONMENT=Development）
cd frontend && npm ci && npm run dev        # 前端 http://localhost:5173，/api 轉給後端
dotnet ef migrations add <名稱>             # 改了 Data/ 的模型後產生新的 Migration（需要 dotnet-ef 工具）
```
