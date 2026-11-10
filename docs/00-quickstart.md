# 環境啟動快速版

> DevOps 實作課｜照順序貼指令，把上課環境跑起來。第一次安裝 Docker、或想看每一步的說明，請看[完整版 00](00-setup.md)。
> 指令有分就挑自己的系統；沒分的兩邊一樣。macOS 已實測，Windows 指令尚未在教室電腦實測，畫面不同請舉手。

## 1. 確認 Docker 開著

先打開 Docker Desktop，等到顯示 **Engine running**。

```bash
docker version --format '{{.Server.Version}}'
docker compose version
```

兩行都印出版本號就對了。

## 2. 取得檔案，進到 `devops-lab`

```bash
git clone https://github.com/Lung-Yu/devops-lab.git
cd devops-lab
```

沒有 git：到 <https://github.com/Lung-Yu/devops-lab> 按 **Code → Download ZIP**，解壓後進 `devops-lab-main`。

已經 clone 過：在 `devops-lab` 裡跑 `git pull` 更新。之後所有指令都在 `devops-lab` 這一層（看得到 `docker-compose.yml` 的地方）執行。

## 3. 環境檢查

**PowerShell（Windows）**

```powershell
powershell -ExecutionPolicy Bypass -File tools\selftest.ps1 env
```

**bash（macOS／Linux）**

```bash
bash tools/selftest.sh env
```

最後一行要是 `FAIL 0`。image 還沒準備時出現 WARN 沒關係，第 5 步會補。

## 4. 啟動資料庫與 mock 服務

```bash
docker compose up -d mock-db mock-external-api
docker compose ps
```

等 10–20 秒，`mock-db` 要顯示 `(healthy)`、`mock-external-api` 要顯示 `Up`。

## 5. 準備範例網站的 image

先看 image 在不在：

```bash
docker image ls keypasco-lab-api
```

有列出 `keypasco-lab-api` 就跳到第 6 步。沒有的話二選一：

```bash
# A. 自己 build（網路順、Mac 用這條；第一次約 1–3 分鐘以上）
docker build -t keypasco-lab-api apps/dotnet-deploylog

# B. 教室網路慢：跟講師拿 keypasco-lab-images-amd64.tar，放進 devops-lab 後載入
docker load -i keypasco-lab-images-amd64.tar
```

## 6. 建資料表、啟動網站

```bash
docker run --rm --env-file .env.poc --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal keypasco-lab-api migrate
docker run -d --name lab-api -p 5000:5000 --env-file .env.poc --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal keypasco-lab-api
```

**PowerShell（Windows）**：一定要打 `curl.exe`

```powershell
curl.exe http://localhost:5000/health
curl.exe http://localhost:5000/health/ready
curl.exe http://localhost:5000/whoami
```

**bash（macOS／Linux）**

```bash
curl http://localhost:5000/health
curl http://localhost:5000/health/ready
curl http://localhost:5000/whoami
```

應該看到：

```text
Healthy
Healthy
{"environment":"POC","dbHost":"host.docker.internal","dbName":"labdb_poc"}
```

瀏覽器開 <http://localhost:5000>，可用 `admin`、`engineer`、`viewer` 登入，密碼都是 `Lab@2026`（只用於本機練習）。

**到這裡環境就準備好了。**

## 7. Java 組加碼：啟動 Spring Boot 範例

第一次要下載 Maven、JDK 和套件，約 2–5 分鐘，需要連得到 Docker Hub 和 Maven Central。教室網路塞住就先跟著投影片，課後再做。

```bash
docker build -t deploylog-spring apps/java-spring-demo
```

**PowerShell（Windows）**

```powershell
$H = @('--add-host=host.docker.internal:host-gateway', '-e', 'DB_HOST=host.docker.internal')
docker run -d --name spring-api -p 8080:8080 --env-file .env.poc -e SPRING_PROFILES_ACTIVE=poc @H deploylog-spring
curl.exe http://localhost:8080/actuator/health
```

**bash／zsh（macOS／Linux）**

```bash
H=(--add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal)
docker run -d --name spring-api -p 8080:8080 --env-file .env.poc -e SPRING_PROFILES_ACTIVE=poc "${H[@]}" deploylog-spring
curl http://localhost:8080/actuator/health
```

等 10 秒左右，應該看到 `{"status":"UP","groups":["liveness","readiness"]}`。後續實驗見 [09 Java 組](09-java-spring-demo.md)。

## 卡住時

| 你看到 | 處理 |
|--------|------|
| `docker` 找不到、`error during connect` | 打開 Docker Desktop，等 Engine running；重開一個終端機 |
| `running scripts is disabled` | 照第 3 步的完整指令，不要直接打 `.\tools\selftest.ps1` |
| `請在 devops-lab/ 根目錄下執行`、`no configuration file provided` | `cd` 回 `devops-lab` |
| PowerShell 印出一大串 `StatusCode` | 改打 `curl.exe` |
| `port is already allocated`（5432） | 暫停電腦上原本的 PostgreSQL |
| Port 5000 被佔用（Mac 的 AirPlay） | 改成 `-p 5050:5000`，網址的 5000 改 5050 |
| Port 8080 被佔用 | 改成 `-p 8090:8080`，網址的 8080 改 8090 |
| `container name ... is already in use` | `docker rm -f lab-api`（Java 組是 `spring-api`），再執行一次 |
| `/health/ready` 是 `Unhealthy` | 再跑一次第 6 步的 `migrate`，不用重啟網站 |
| image 不見了（教室電腦重開機被還原） | 重做第 4、5 步 |

**全部重來**（會清掉練習資料庫）：

```bash
docker rm -f lab-api spring-api
docker compose down -v
```

然後從第 4 步開始。還是不行，把 `selftest env` 的結果截圖給講師。
