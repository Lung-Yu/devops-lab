# Spring Boot 對照範例（Java 組加碼）

課堂 Lab 用的是 .NET 的 DeployLog（`../apps/dotnet-deploylog/`）。這個資料夾把 **M2 組態、M4 預檢與健康檢查、M5 結構化日誌、M6 Schema 版本管理** 用 Java Spring Boot 再做一次，讓 Java 背景的同學對照：概念一樣，只是寫法不同。

- Spring Boot 3.4.1、Java 17、Flyway 10、PostgreSQL 16
- 跟 DeployLog 共用同一套環境：同一個 `mock-db`、同一份 `.env.dev`／`.env.qa`／`.env.poc`
- **只需要 Docker**，不用裝 JDK 或 Maven（編譯在 Docker 裡做）

> 課堂時間不夠時這份可以課後自己跑。每個實驗獨立，挑想看的做就好。

---

## 0. 先看這段：Windows 和 Mac 的指令差在哪

下面每個步驟都分成 **Windows（PowerShell）** 和 **macOS（終端機）** 兩段，抄自己那段就好。

| | Windows | macOS |
|---|---|---|
| 用哪個程式下指令 | **PowerShell**（開始選單搜尋「PowerShell」）。不要用「命令提示字元 cmd」或 Git Bash，下面的指令在那兩個裡會出錯 | 「終端機」（Terminal），zsh 或 bash 都可以 |
| 一行太長要換行 | 行尾加 **反引號 `` ` ``**（鍵盤左上角、數字 1 左邊），反引號**後面不能有空白** | 行尾加 **反斜線 `\`**，後面不能有空白 |
| 呼叫網址 | 用 **`curl.exe`**（Windows PowerShell 的 `curl` 是另一個指令，輸出不一樣） | 用 `curl` |
| 目前資料夾 | `${PWD}` | `$PWD` |
| 在輸出裡找字 | `Select-String "關鍵字"` | `grep "關鍵字"` |
| 路徑 | `apps\java-spring-demo\src\...`（`/` 也可以） | `apps/java-spring-demo/src/...` |

不想看指令輸出也行：所有 `curl` 的網址都可以直接貼到瀏覽器打開。

**Mac 是 Apple Silicon（M1～M4）也沒問題**，用到的 image 都有 ARM 版本。

---

## 1. 準備環境

開 PowerShell／終端機，切到 repo 的 `devops-lab/` 資料夾（之後所有指令都在這裡下）：

```powershell
# Windows：路徑換成你實際 clone 或解壓的位置
cd C:\Users\你的帳號\devops-lab
```

```bash
# macOS
cd ~/devops-lab
```

確認 Docker 有在跑（Docker Desktop 的鯨魚圖示是穩定狀態），然後啟動資料庫和假的外部服務：

```bash
# Windows、macOS 都一樣
docker compose up -d mock-db mock-external-api
docker compose ps
```

`mock-db` 的 STATUS 出現 `healthy` 再往下。

## 2. 建置 image

```bash
# Windows、macOS 都一樣（第一次約 2–5 分鐘，要下載 Maven、JDK 和套件）
docker build -t deploylog-spring apps/java-spring-demo
```

最後出現 `naming to docker.io/library/deploylog-spring` 或 `Successfully tagged deploylog-spring` 就是成功。

## 3. 用 POC 環境的設定啟動

```powershell
# Windows
docker run -d --name spring-api -p 8080:8080 `
  --env-file .env.poc -e SPRING_PROFILES_ACTIVE=poc `
  --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal `
  deploylog-spring
```

```bash
# macOS
docker run -d --name spring-api -p 8080:8080 \
  --env-file .env.poc -e SPRING_PROFILES_ACTIVE=poc \
  --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal \
  deploylog-spring
```

每個參數在做什麼：

| 參數 | 意思 | 對照 DeployLog |
|------|------|---------------|
| `--env-file .env.poc` | 讀 POC 環境的設定（`DB_NAME=labdb_poc`、`EXTERNAL_API_URL`…） | 同一個檔案 |
| `-e SPRING_PROFILES_ACTIVE=poc` | 告訴 Spring 現在是 POC 環境，載入 `application-poc.yml` | .NET 看的是 `.env` 裡的 `ASPNETCORE_ENVIRONMENT`；Spring 不認這個變數，所以另外指定 |
| `-e DB_HOST=host.docker.internal` | 容器裡的 `localhost` 是容器自己，要用這個名字才連得回你電腦上的 mock-db | 一樣 |
| `-p 8080:8080` | 用 8080，不跟 DeployLog 的 5000 衝突，兩個可以同時開 | — |

等 10 秒左右，確認啟動成功：

```powershell
# Windows
docker logs spring-api
curl.exe localhost:8080/actuator/health
```

```bash
# macOS
docker logs spring-api
curl localhost:8080/actuator/health
```

看到 `{"status":"UP",...}` 就成功了。

---

## 實驗 A：健康檢查分兩種（M4）

```powershell
# Windows
curl.exe localhost:8080/actuator/health/liveness
curl.exe localhost:8080/actuator/health/readiness
```

```bash
# macOS
curl localhost:8080/actuator/health/liveness
curl localhost:8080/actuator/health/readiness
```

兩個都是 `UP`。現在把資料庫停掉，再查一次（指令同上）：

```bash
# Windows、macOS 都一樣
docker compose stop mock-db
```

| 端點 | 意思 | DB 停掉後 |
|------|------|----------|
| `/actuator/health/liveness` | 程式本身還活著嗎？（掛了就該重開） | **200 UP** |
| `/actuator/health/readiness` | 現在能接請求嗎？（含 DB 連線） | **503 DOWN** |
| `/actuator/health` | 整體 | **503 DOWN** |

**重點**：DB 掛了不代表要重開服務，重開也沒用。Kubernetes 之類的平台用 liveness 決定要不要重開、用 readiness 決定要不要導流量進來。設定在 `application.yml` 的 `management.endpoint.health`。

做完把 DB 開回來，幾秒後 readiness 會自己變回 UP：

```bash
docker compose start mock-db
```

## 實驗 B：必填設定沒給，就不要啟動（M4 預檢 0）

先把剛剛的容器刪掉，再故意把 `EXTERNAL_API_URL` 設成空的啟動：

```powershell
# Windows
docker rm -f spring-api
docker run --rm --env-file .env.dev -e SPRING_PROFILES_ACTIVE=dev -e EXTERNAL_API_URL= `
  --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal `
  deploylog-spring
echo "exit code: $LASTEXITCODE"
```

```bash
# macOS
docker rm -f spring-api
docker run --rm --env-file .env.dev -e SPRING_PROFILES_ACTIVE=dev -e EXTERNAL_API_URL= \
  --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal \
  deploylog-spring
echo "exit code: $?"
```

會看到：

```
APPLICATION FAILED TO START
    Property: app.externalApiUrl
    Reason: must not be blank
exit code: 1
```

做法在 `src/main/java/demo/App.java`：設定綁到一個 `record`，欄位加 `@NotBlank`，類別加 `@Validated`。Spring 啟動時就檢查，不用等到第一個請求打進來才發現。這跟 M4 的 `start.sh` 預檢是同一個想法：**有缺就在門口擋下，錯誤訊息講清楚缺什麼**。

（這裡用 dev profile 是因為它的 log 是一般文字，比較好讀；POC 的 log 是 JSON，同一段訊息會擠在一行裡。）

## 實驗 C：同一個 image，換 profile 就換行為（M2＋M5）

用 dev 和 poc 各啟動一次，比較 log 長相（`Ctrl+C` 停止）：

```powershell
# Windows
docker run --rm --env-file .env.dev -e SPRING_PROFILES_ACTIVE=dev `
  --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal deploylog-spring
docker run --rm --env-file .env.poc -e SPRING_PROFILES_ACTIVE=poc `
  --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal deploylog-spring
```

```bash
# macOS
docker run --rm --env-file .env.dev -e SPRING_PROFILES_ACTIVE=dev \
  --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal deploylog-spring
docker run --rm --env-file .env.poc -e SPRING_PROFILES_ACTIVE=poc \
  --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal deploylog-spring
```

| profile | 設定檔 | log 長相 |
|---------|--------|---------|
| `dev` | `application-dev.yml` | 一般文字，人好讀；看得到 DEBUG |
| `qa` | `application-qa.yml` | JSON（ECS 格式），INFO 以上 |
| `poc` | `application-poc.yml` | JSON，只剩 WARN 以上（Flyway 的紀錄例外保留） |

POC 的那行 `Order failed` 長這樣：

```json
{"log.level":"ERROR","log.logger":"demo.App","message":"Order failed","orderId":12345,"reason":"payment gateway timeout",...}
```

`orderId`、`reason` 是**獨立欄位**，不是塞在訊息字串裡。log 系統（ELK、Loki）可以直接用 `orderId = 12345` 搜尋，不用寫正規表示式去拆字串。程式寫法在 `App.java` 的 `log.atError().addKeyValue(...)`；JSON 格式是 Spring Boot 3.4 內建的，只要 `application.yml` 一行 `logging.structured.format.console: ecs`。

**重點**：三個環境跑的是**同一顆 image**，差別只在啟動時給的設定。不需要為每個環境各打包一次（M1 不可變交付物、M2 組態解耦）。

## 實驗 D：Schema 版本管理與「改舊檔」會怎樣（M6）

Migration 檔在 `src/main/resources/db/migration/`：

```
V1__create_orders.sql       建 orders 表
V2__add_order_status.sql    加 status 欄位
```

前面每次啟動，Spring 都會自動跑 Flyway。第一次的 log 會看到：

```
Migrating schema "spring_demo" to version "1 - create orders"
Migrating schema "spring_demo" to version "2 - add order status"
```

之後再啟動就只會說已經是最新版。版本紀錄存在資料庫的 `spring_demo.flyway_schema_history` 表。

> 為什麼是 `spring_demo` schema：DeployLog 的表也在同一個資料庫，分開放才不會互相干擾。

**現在故意改已經套用過的 V2**：用編輯器打開 `apps/java-spring-demo/src/main/resources/db/migration/V2__add_order_status.sql`，把 `'NEW'` 改成 `'PENDING'`，存檔。重新建 image 再啟動：

```powershell
# Windows
docker build -t deploylog-spring apps/java-spring-demo
docker run --rm --env-file .env.poc -e SPRING_PROFILES_ACTIVE=poc `
  --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal deploylog-spring
```

```bash
# macOS
docker build -t deploylog-spring apps/java-spring-demo
docker run --rm --env-file .env.poc -e SPRING_PROFILES_ACTIVE=poc \
  --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal deploylog-spring
```

服務起不來：

```
Migration checksum mismatch for migration version 2
-> Applied to database : 1665690257
-> Resolved locally    : 1929741163
```

Flyway 記得每個版本檔當初的指紋，檔案被改過就拒絕啟動。**已經上線的 migration 不能改，要改就新增 V3。** 不然 Dev 跑的是新版 V2、客戶那台跑的是舊版 V2，兩邊 Schema 就不一樣了。

做完**一定要改回來**再重建 image，否則後面的實驗都會卡在這裡：

```bash
# Windows、macOS 都一樣（用 git clone 的才有這個指令；ZIP 下載的請手動把 'PENDING' 改回 'NEW'）
git checkout -- apps/java-spring-demo/src/main/resources/db/migration/V2__add_order_status.sql
docker build -t deploylog-spring apps/java-spring-demo
```

## 實驗 E：正式環境把 migrate 拆出來（M6）

Spring Boot 預設**每個實例啟動時都自己跑 migrate**。開發時方便，但正式環境開三個實例就是三個人同時改 Schema。M6 的做法是：服務啟動時不碰 Schema，migrate 由 CI 或部署流程單獨跑一次。

用 QA 環境示範。先關掉自動 migrate 啟動服務：

```powershell
# Windows
docker run -d --name spring-api -p 8080:8080 `
  --env-file .env.qa -e SPRING_PROFILES_ACTIVE=qa -e SPRING_FLYWAY_ENABLED=false `
  --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal `
  deploylog-spring
```

```bash
# macOS
docker run -d --name spring-api -p 8080:8080 \
  --env-file .env.qa -e SPRING_PROFILES_ACTIVE=qa -e SPRING_FLYWAY_ENABLED=false \
  --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal \
  deploylog-spring
```

`docker logs spring-api` 裡不會出現 Flyway 的紀錄（`SPRING_FLYWAY_ENABLED` 對應 yml 的 `spring.flyway.enabled`，Spring 會自動把環境變數名稱轉過去）。

再用官方的 Flyway image 單獨跑 migrate，讀的是同一份 SQL 檔：

```powershell
# Windows
docker run --rm --add-host=host.docker.internal:host-gateway `
  -v "${PWD}/apps/java-spring-demo/src/main/resources/db/migration:/flyway/sql" `
  flyway/flyway:10 `
  -url=jdbc:postgresql://host.docker.internal:5432/labdb_qa `
  -user=labuser -password=labpass -schemas=spring_demo migrate
```

```bash
# macOS
docker run --rm --add-host=host.docker.internal:host-gateway \
  -v "$PWD/spring-demo/src/main/resources/db/migration:/flyway/sql" \
  flyway/flyway:10 \
  -url=jdbc:postgresql://host.docker.internal:5432/labdb_qa \
  -user=labuser -password=labpass -schemas=spring_demo migrate
```

```
Successfully applied 2 migrations to schema "spring_demo", now at version v2
```

（如果你之前已經用 QA 環境開著自動 migrate 跑過，這裡會說已經是最新版，一樣是對的。）

> 代價：開著自動 migrate 時，DB 連不上服務就起不來，等於多一道預檢；關掉之後這道保護就沒了，要靠 readiness（實驗 A）補上。

## 實驗 F（選做）：少一個冒號的陷阱（M4）

打開 `apps/java-spring-demo/src/main/resources/application.yml`，最後一行：

```yaml
  external-api-url: ${EXTERNAL_API_URL:}
```

把冒號刪掉變成 `${EXTERNAL_API_URL}`，重建 image，再做一次實驗 B。

結果：**服務照常啟動**。變數沒設時，Spring 會把字面字串 `${EXTERNAL_API_URL}` 當成值，它不是空的，所以 `@NotBlank` 擋不下來。`docker logs` 裡 `externalApiUrl` 的值會是 `${EXTERNAL_API_URL}`。

這跟 M4 的 `start-naive.sh` 是同一種問題：**看起來啟動了，其實設定是錯的**。做完記得把冒號加回去（或 `git checkout -- apps/java-spring-demo/src/main/resources/application.yml`）再重建。

---

## 收拾

```bash
# Windows、macOS 都一樣
docker rm -f spring-api
docker compose stop
```

想連 image 一起刪：`docker rmi deploylog-spring`。

## 常見問題

| 狀況 | 原因與處理 |
|------|-----------|
| `port is already allocated`，8080 被佔用 | 改成 `-p 8090:8080`，網址跟著改 `localhost:8090`。Windows 查誰佔用：`netstat -ano \| findstr :8080`；Mac：`lsof -iTCP:8080 -sTCP:LISTEN` |
| `docker compose up` 說 5432 被佔用 | 你電腦上本來就有裝 PostgreSQL。先把它停掉（Windows：「服務」裡停 postgresql；Mac：`brew services stop postgresql`） |
| `Conflict. The container name "/spring-api" is already in use` | 上一次的容器還在：`docker rm -f spring-api` 再跑 |
| `Connection to host.docker.internal:5432 refused` | mock-db 沒開或還沒 healthy：`docker compose ps` 確認 |
| Windows：`curl` 跑出一大堆 `StatusCode`、`Content` | 打成 `curl` 了，要打 `curl.exe` |
| Windows：換行的指令跑一半就出錯 | 反引號後面多了空白，或複製時反引號變成別的符號。也可以把整段接成一行再貼 |
| Windows：`-v` 那行說找不到路徑 | 確認是在 PowerShell 而不是 Git Bash／cmd，而且目前位置是 `devops-lab/` |
| 實驗 D 之後每次啟動都 checksum mismatch | V2 沒改回來，或改回來了但沒重建 image |
| Linux 使用者 | 指令同 macOS；`--add-host=host.docker.internal:host-gateway` 已經處理了 Linux 沒有這個名字的問題 |

---

## 選讀：不用 Docker、直接用 JDK 跑

給平常就寫 Java、電腦有 **JDK 17 以上和 Maven 3.9** 的同學。資料庫一樣用 `docker compose up -d mock-db`，這時服務在你電腦上跑，所以 `DB_HOST=localhost` 就連得到。

```powershell
# Windows（PowerShell）：環境變數用 $env:名稱 設定，只在這個視窗有效
cd apps/java-spring-demo
mvn -DskipTests package
$env:DB_HOST="localhost"; $env:DB_PORT="5432"; $env:DB_NAME="labdb"
$env:DB_USER="labuser"; $env:DB_PASSWORD="labpass"
$env:EXTERNAL_API_URL="http://localhost:8081"; $env:SPRING_PROFILES_ACTIVE="dev"
java -jar target\deploylog-spring-1.0.0.jar
```

```bash
# macOS：變數寫在指令前面，只對這一次執行有效
cd apps/java-spring-demo
mvn -DskipTests package
DB_HOST=localhost DB_PORT=5432 DB_NAME=labdb DB_USER=labuser DB_PASSWORD=labpass \
EXTERNAL_API_URL=http://localhost:8081 SPRING_PROFILES_ACTIVE=dev \
java -jar target/deploylog-spring-1.0.0.jar
```

Mac 注意：zsh 不會把沒加引號的變數拆開，`E="A=1 B=2"; env $E java ...` 這種寫法會把整串當成一個變數。照上面直接寫在指令前面就好。

---

## 檔案導覽與 .NET 對照

| 檔案 | 內容 | DeployLog（.NET）對應 |
|------|------|---------------------|
| `pom.xml` | 套件清單；版本由 Spring Boot parent 統一管理 | `MyApi.csproj`＋`packages.lock.json` |
| `Dockerfile` | 兩階段：Maven 編譯 → 只放 JRE 執行 | `apps/dotnet-deploylog/Dockerfile` |
| `src/main/resources/application.yml` | 共用設定；`${DB_HOST}` 從環境變數讀 | `appsettings.json` |
| `application-dev.yml`／`-qa.yml`／`-poc.yml` | 各環境覆寫 | `appsettings.Development.json`／`.QA.json`／`.POC.json` |
| `src/main/java/demo/App.java` | 必填設定檢查（`@NotBlank`）、結構化日誌示範 | `RequiredSettings.cs`、`Program.cs` |
| `src/main/resources/db/migration/` | Flyway 版本檔，檔名就是版本號 | `Migrations/`（EF Core） |
| Actuator `/actuator/health/liveness`、`/readiness` | 健康檢查 | `/health`、`/health/ready` |
| Spring 啟動時自動 migrate（可關） | Schema 變更 | `migrate` 指令（預設就是分開跑） |

兩邊最大的差別在最後一列：DeployLog 從一開始就把 migrate 做成獨立指令；Spring Boot 預設是啟動時自動跑，正式環境要自己記得關掉（實驗 E）。

這份範例刻意不含 API 和畫面，只留對照用得到的部分。
