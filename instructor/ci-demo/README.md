# 本機示範 GitLab（講師用）

在講師自己的電腦上跑一台拋棄式的 GitLab CE 19.4＋Runner，用來在課堂上**現場示範 M3 的 CI pipeline、環境切換與發版**。學員不用跑這個；學員的 GitLab 練習看 [docs/03a](../../docs/03a-gitlab-from-zero.md)。

不連外、不用註冊帳號。這裡的帳號密碼和 token 都只在這台拋棄式 GitLab 有效，**不要拿去用在真的系統**。

## 這個資料夾有什麼

| 檔案 | 做什麼 |
|------|--------|
| `docker-compose.yml` | 三個容器：`gitlab`（網頁＋Container Registry）、`runner`（跑 CI job）、`demo-db`（部署出來的網站共用的 PostgreSQL） |
| `setup.sh` | 把 GitLab 設定好並推程式碼觸發 pipeline，可以重複跑（細節見下面「setup.sh 做了什麼」） |
| `.gitlab-ci.yml` | 示範專案的 pipeline。程式碼本身不放在這裡：setup.sh 會複製 [`labs/m3-ci-pipeline/sample-repo/`](../../labs/m3-ci-pipeline/sample-repo/)（學員 M3 練習用的同一份），再加上這份 yml |

`.gitlab-ci.yml` 跟學員版的 [`labs/m3-ci-pipeline/gitlab-ci-dotnet-example.yml`](../../labs/m3-ci-pipeline/gitlab-ci-dotnet-example.yml) 比起來，多了三樣東西：示範變數遮罩的 `secrets-demo` job，以及 `deploy`、`release` 兩個 stage。

## 開始前確認

- Docker Desktop 開著，而且分給 Docker 的記憶體至少 6 GB（GitLab 自己就吃約 3 GB）。
- 這些 port 沒被佔用：8929（GitLab 網頁）、5050（Registry）、8001／8002／8003（部署出來的 dev／qa／poc）。
- 瀏覽器要看得懂 `gitlab` 這個主機名稱。GitLab 的網址設成 `http://gitlab:8929`，這樣 Runner 的 job 容器才連得到它。所以本機要在 `/etc/hosts` 加一行（只要做一次）：

  ```bash
  echo '127.0.0.1 gitlab' | sudo tee -a /etc/hosts
  ```

> ⚠️ **Mac 的 port 5050 會撞到**：Mac 的 5000 被 AirPlay 佔用時，學員手冊教大家把範例網站改開在 5050。可是講師電腦還要跑這台 GitLab，它的 Registry 也用 5050。所以講師電腦上的範例網站請開在別的 port，例如 `-p 5055:5000`；selftest 就用 `LAB_PORT=5055`。

## 第一次啟動（含等待約 25 分鐘）

所有指令都在這個資料夾（`devops-lab/instructor/ci-demo`）下執行：

```bash
# 1. 起 GitLab：第一次要初始化，約 10 分鐘
docker compose up -d

# 2. 等登入頁打得開（回 200 才往下）
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8929/users/sign_in

# 3. 設定專案、變數、Runner，推四個版本觸發 pipeline
bash setup.sh
```

第 3 步跑完後，pipeline 還要再跑**大約 12–13 分鐘**才會全部結束，所以要在上課前提早做。

用 Podman（rootless）而不是 Docker Desktop 的話，第 1 步前要先 `export CONTAINER_SOCKET=/run/user/501/podman/podman.sock`，Runner 才拿得到 VM 裡的 socket。

## 登入

打開 <http://localhost:8929>：

- 帳號：`root`
- 密碼：`Keypasco-Demo-2026!`（**最後有一個驚嘆號**）

這組密碼只在 GitLab **第一次初始化**時生效。之後就算改了 `docker-compose.yml` 裡的值，也要 `docker compose down -v` 刪掉資料重建，新密碼才會生效。

## 確認一切正常

pipeline 跑完後，打開 <http://localhost:8929/root/keypasco-demo/-/pipelines>，應該有四條：

| 分支／tag | 結果 | 用途 |
|-----------|------|------|
| `main`（第一版） | ✅ 綠燈，`deploy-dev` 已部署、`deploy-qa` 等手動放行 | dev 的第一筆部署 |
| `v1.0.0` | ✅ 綠燈，產生 Release，`deploy-poc` 等手動放行 | 發版示範 |
| `main`（第二版，加 CHANGELOG） | ✅ 綠燈，`deploy-dev` 已部署 | dev 的第二筆部署，讓 Rollback 有東西可以退 |
| `feature/break-test` | ❌ `test` 紅燈，後面全部 skipped | 示範測試沒過就不會往下 |

這時 <http://localhost:8001/whoami> 應該回 `{"environment":"Development",...}`。8002、8003 要等課堂上按 ▶ 放行才會有服務。

## 課堂現場示範路線

1. **Settings → CI/CD → Variables**：`DB_NAME`、`ASPNETCORE_ENVIRONMENT` 各有 dev／qa／poc 三個 Environment scope，等於把 M2 的 `.env.*` 搬進 GitLab；`DB_HOST`、`DB_USER`、`DB_PASSWORD`（Masked）三個環境共用。
2. **Operate → Environments**：dev 有兩筆部署，在舊的那筆按 **Rollback**，再開 <http://localhost:8001> 看版本換回來。
3. 回到 main 的 pipeline，按 `deploy-qa` 的 **▶** 放行，再開 <http://localhost:8002/whoami>，會看到環境變成 QA。
4. **Deploy → Releases**：看 `v1.0.0`。

時間不夠的話只做 2 和 4。

Rollback 和 ▶ 按下去就用掉了。要再示範一次，重跑 `bash setup.sh`，它會把狀態還原。

## 三個環境怎麼部署

| Job | 什麼時候跑 | 部署到 |
|-----|-----------|--------|
| `deploy-dev` | main 每次 push 自動跑 | http://localhost:8001 |
| `deploy-qa` | main，手動放行（▶） | http://localhost:8002 |
| `deploy-poc` | 只有 tag，手動放行 | http://localhost:8003 |
| `release` | tag | Deploy → Releases |

- 三個環境用**同一個 image**，差別只在 Environment scope 變數。
- 每個 deploy job 依序做四件事：
  1. 拉 image；
  2. 跑 `migrate`（M6）；
  3. 換掉舊容器；
  4. 等 `/health/ready` 回 200（M4），沒 ready 就亮紅燈。
- 有兩台 Runner：
  - **一般用**：docker-build 用它自己的 dind。
  - **部署用**（tag `deploy`）：掛講師電腦的 Docker socket，直接在本機起容器。真實環境對應的是裝在部署機上的 Runner。掛 socket 只限這個拋棄式環境。

## setup.sh 做了什麼

1. 用 `gitlab-rails` 幫 root 建一個 API token，並關掉版本檢查（不然投影時會跳出「Critical patch release」視窗）。
2. 建專案 `root/keypasco-demo`；已經存在就沿用。
3. 重建 CI 變數：一般、Masked、Masked＋Protected 三種，再加上 dev／qa／poc 的 Environment scope 變數。
4. 刪掉舊 Runner，重新註冊兩台（一般用＋部署用）。
5. 清掉上一輪留下的東西：pipeline、image tag、Environments、Release，以及部署出來的容器。
6. 推四個版本：`main` → tag `v1.0.0` → `main` 第二版 → `feature/break-test`。

## 用完收掉

```bash
docker compose stop        # 停掉，保留資料，下次 up -d 很快就好
docker compose down        # 刪容器、保留 GitLab 資料；demo-db 會變空，下次要重跑 setup.sh
docker compose down -v     # 連 GitLab 資料一起刪，下次等於第一次啟動
docker rm -f deploylog-dev deploylog-qa deploylog-poc   # 部署出來的網站不屬於這個 compose，要另外刪
```

## 卡住時

| 你看到 | 處理 |
|--------|------|
| 登入說密碼錯 | 密碼最後有 `!`；密碼只在第一次初始化時生效，見「登入」 |
| 登入後跳到 `http://gitlab:8929/...` 打不開 | `/etc/hosts` 沒加 `127.0.0.1 gitlab`，見「開始前確認」 |
| `docker compose up` 說 port 5050 被佔用 | 講師電腦的範例網站改開在 5055，見上面的 ⚠️ |
| pipeline 一直卡在 pending | Runner 沒註冊好：重跑 `bash setup.sh` |
| 8001 打不開 | `deploy-dev` 還沒跑完；或之前跑過 `docker compose down`，demo-db 被清空，要重跑 `bash setup.sh` |
