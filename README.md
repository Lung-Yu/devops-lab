# devops-lab

DevOps 實作課（兩天、六個模組）的 Lab 專案。整門課都用同一個範例網站 **DeployLog** 練習：Vue3＋ASP.NET Core 10＋PostgreSQL，打包成一個 Docker image。

**你只需要裝 Docker**。.NET、Node、Java 都在容器裡跑，不用另外安裝。

---

## 第一次來：照這個順序

1. **裝好 Docker Desktop**，打開並等它顯示 Engine running。還沒裝的話，照 [docs/00 環境準備](docs/00-setup.md) 從頭做。
2. **取得這個專案，然後進到資料夾裡**。之後所有指令都在這一層（看得到 `docker-compose.yml` 的地方）下：

   ```bash
   git clone https://github.com/Lung-Yu/devops-lab.git
   cd devops-lab
   ```

   沒有 git 的話，按 GitHub 頁面上的 **Code → Download ZIP**，解壓後進到 `devops-lab-main`，用法完全一樣。
3. **跑環境檢查**，最後一行要是 `FAIL 0`：

   ```powershell
   # Windows（PowerShell）
   powershell -ExecutionPolicy Bypass -File tools\selftest.ps1 env
   ```

   ```bash
   # macOS／Linux
   bash tools/selftest.sh env
   ```

4. **把環境跑起來**：照 [docs/00-quickstart.md](docs/00-quickstart.md) 貼指令，約 5 分鐘。最後打開 <http://localhost:5000> 看到登入畫面就完成了。
5. **開始上課**：照 [docs/README.md](docs/README.md) 的課程地圖，從 M1 一章一章做。

---

## 資料夾地圖：哪個是什麼

```
devops-lab/                  ← 所有指令都在這一層下
├── docker-compose.yml       課堂共用的 mock 服務：PostgreSQL＋假的外部 API
├── .env.dev .env.qa .env.poc    三個環境的設定檔（.env.example 是範本）
│
├── apps/                    範例程式：被建置、被部署的對象
│   ├── dotnet-deploylog/    ★ 主角：範例網站 DeployLog（.NET 10＋Vue3），M1–M6 都用它
│   └── java-spring-demo/    Java 組加碼：用 Spring Boot 把 M2／M4／M5／M6 再做一次
│
├── labs/                    各模組 Lab 的練習檔
│   ├── m3-ci-pipeline/      M3：要推上 GitLab 的範例程式＋兩份 .gitlab-ci.yml 範例
│   └── m4-preflight/        M4：部署前預檢腳本（starter/ 起始檔、solution/ 參考解答）
│
├── mock-services/           docker-compose.yml 用到的設定（資料庫初始化、假外部 API）
├── tools/                   selftest 環境與 Lab 自我檢查；講師用離線 image 打包
├── docs/                    手把手教程：每一步的指令、預期結果、卡住怎麼辦
└── instructor/
    └── ci-demo/             講師用：本機示範 GitLab（學員不用跑）
```

### 每個模組用到哪裡

| 模組 | 在做什麼 | 用到的檔案 | 教程 |
|------|---------|-----------|------|
| M1 可維運性思維 | 啟動 DeployLog，用三種角色逛一圈 | `apps/dotnet-deploylog/`、`docker-compose.yml` | [01](docs/01-m1-operability.md) |
| M2 組態解耦 | 同一個 image，換 `.env` 就切換 Dev／QA／POC | `.env.dev`／`.env.qa`／`.env.poc` | [02](docs/02-m2-config.md) |
| M3 CI Pipeline | 讀懂並寫出 `.gitlab-ci.yml`，推上 GitLab 跑 | `labs/m3-ci-pipeline/` | [03](docs/03-m3-ci-pipeline.md)、[03a](docs/03a-gitlab-from-zero.md)、[03b](docs/03b-gitlab-environments-release.md) |
| M4 部署腳本與預檢 | 寫一支「環境不對就拒絕啟動」的腳本 | `labs/m4-preflight/` | [04](docs/04-m4-deploy-scripts.md) |
| M5 日誌與排查 | 用追蹤編號從錯誤畫面找到那一行 log | `apps/dotnet-deploylog/` | [05](docs/05-m5-logging.md) |
| M6 DB Schema 管理 | `migrate` 指令、打錯 DB 名稱被擋 | `apps/dotnet-deploylog/` | [06](docs/06-m6-db-migration.md) |
| Java 組加碼 | 同樣的概念用 Spring Boot 實際跑 | `apps/java-spring-demo/` | [09](docs/09-java-spring-demo.md) |

每個子資料夾都有自己的 README，說明裡面每個檔案是做什麼的、怎麼跑。

---

## 會用到的 port

| Port | 是誰 | 被佔用時 |
|------|------|---------|
| 5000 | 範例網站 DeployLog | Mac 的 AirPlay 會佔用：把 `-p 5000:5000` 改成 `-p 5050:5000`，網址的 5000 改 5050 |
| 5432 | mock-db（PostgreSQL） | 先暫停電腦上原本的 PostgreSQL |
| 8081 | mock-external-api（假外部服務） | — |
| 8080 | Java 組的 Spring Boot 範例 | 改成 `-p 8090:8080` |

---

## 用完收掉

```bash
docker rm -f lab-api spring-api   # 自己用 docker run 起的網站
docker compose down               # mock 服務；加 -v 會連練習資料庫一起清掉
```

Docker Desktop 裡，mock 服務會歸在 **devops-lab** 這一組。

---

## 關於帳號密碼

檔案裡出現的密碼都是**只在你自己電腦上跑的練習環境**用的假值，不連任何真實系統，例如網站帳號的 `Lab@2026`、資料庫的 `labpass`、示範 GitLab 的 `labpass-demo`。拿這份專案改成自己的專案時，請換掉。
