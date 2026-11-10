# mock-services：課堂用的假依賴服務設定

根目錄的 `docker-compose.yml` 會起兩個服務，代替「客戶環境裡的資料庫」和「網站要呼叫的外部系統」，讓每個人在自己電腦上就能練習，不用連任何真實系統。這個資料夾放的是它們的設定檔，平常不用改。

| 檔案 | 給誰用 | 做什麼 |
|------|--------|--------|
| `mock-db-init.sql` | `mock-db`（PostgreSQL 16，port 5432） | 第一次啟動時多建 `labdb_qa`、`labdb_poc` 兩個資料庫；`labdb` 由 compose 的 `POSTGRES_DB` 建。三個庫分別對應 `.env.dev`／`.env.qa`／`.env.poc` |
| `mock-external-api.conf` | `mock-external-api`（nginx，port 8081） | 一個永遠回 OK 的假外部服務，`/health` 回 200。M4 Lab 用它練「外部服務連不上」的檢查 |

## 常用指令（在 `devops-lab` 根目錄下）

```bash
docker compose up -d mock-db mock-external-api   # 啟動
docker compose ps                                # mock-db 要是 (healthy)
docker compose stop mock-db                      # 模擬「資料庫連不上」（M4、M6）
docker compose stop mock-external-api            # 模擬「外部服務連不上」（M4）
docker compose start mock-db mock-external-api   # 恢復
docker compose down -v                           # 全部刪掉，連資料庫內容一起清
```

`mock-db-init.sql` 只在資料庫**第一次**建立時執行。改了它之後，要 `docker compose down -v` 清掉舊資料，再重新 `up` 才會生效。
