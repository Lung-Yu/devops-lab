# M4 Lab：部署前預檢腳本

**目標**：寫一支啟動腳本，啟動網站前先檢查四件事，任一項不對就印出「哪裡錯、去哪修」並 `exit 1`，不讓壞掉的部署跑起來。

完整步驟、預期輸出、卡住怎麼辦：看 [docs/04 M4 部署腳本與預檢機制](../../docs/04-m4-deploy-scripts.md) Part 2。

## 檔案

| 檔案 | 是什麼 | 你要做什麼 |
|------|--------|-----------|
| `starter/start-naive.sh`／`.ps1` | 反面教材：什麼都不檢查，直接 `docker run` | 跑一次，看「看起來啟動了，其實整個是壞的」 |
| `starter/start.sh`／`.ps1` | **你的起始檔**：骨架寫好了，留四個 TODO | 把四個 TODO 補完 |
| `solution/start.sh`／`.ps1` | 參考解答 | 先自己寫，卡住再看 |

bash 和 PowerShell 各一份，挑你的系統用。

## 四項預檢（TODO 0–3）

| # | 檢查 | 不對的時候 |
|---|------|-----------|
| 0 | 必填設定：`EXTERNAL_API_URL`、`APP_PORT`、`DB_HOST`、`DB_PORT` 都有值 | 少一個就停 |
| 1 | 外部服務：`$EXTERNAL_API_URL/health` 打得通 | 連不到就停 |
| 2 | Port：`$APP_PORT` 沒被別的程式佔用 | 被佔用就停 |
| 3 | 資料庫：`pg_isready` 連得上 | 連不上就停 |

## 怎麼跑

在 `devops-lab` 根目錄下執行（不是在這個資料夾裡）：

```bash
docker compose up -d mock-db mock-external-api      # 先把依賴服務起來
bash labs/m4-preflight/starter/start.sh .env.poc    # macOS／Linux
```

```powershell
powershell -ExecutionPolicy Bypass -File labs\m4-preflight\starter\start.ps1 .env.poc   # Windows
```

## 檢查自己寫對了沒

selftest 會對你的腳本做五種破壞：缺 `DB_HOST`、外部服務停掉、Port 被佔用、`DB_HOST` 打錯、資料庫停掉。每一種都要被擋下來，最後再確認四項全部通過時網站有正常啟動：

```bash
bash tools/selftest.sh m4 labs/m4-preflight/starter/start.sh
```

```powershell
powershell -ExecutionPolicy Bypass -File tools\selftest.ps1 m4 labs\m4-preflight\starter\start.ps1
```

`pg_isready` 是 PostgreSQL client 的指令。電腦上沒有的話，selftest 的環境檢查會提示你。
