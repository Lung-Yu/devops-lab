# 手把手：GitLab 從 0 開始

> DevOps 實作課｜M3 自動化打包與持續整合｜學員自己動手
> 這份文件從「完全沒碰過 GitLab」開始：建帳號、建專案、把程式推上去、讓 Runner 跑第一條 pipeline、看測試失敗怎麼擋住合併、把密碼交給 CI、打版本 tag、找到 image 和產物、留下發版紀錄。**每一步都有截圖**，照著點就做得出來。

---

## 你會學到什麼

| 步驟 | 在 GitLab 哪裡 | 對應課程 |
|------|---------------|---------|
| 建帳號、登入、改密碼 | Admin area → Users；登入頁 | — |
| 建專案、用 token 推程式 | **+** → New project/repository；Edit profile → Access → Personal access tokens | M3：程式碼集中管理 |
| 註冊 Runner（真正跑 job 的機器） | Settings → CI/CD → Runners | M3：打包不能靠某個人的電腦 |
| 寫 `.gitlab-ci.yml`、檢查語法 | Build → Pipeline editor | M3：pipeline 一行一行怎麼讀 |
| 看 pipeline、job log、測試報告 | Build → Pipelines、Jobs；pipeline 的 **Tests** 分頁 | M3：CI 的四個紀律 |
| 測試沒過就不能合併 | Merge request；Settings → Merge requests → **Pipelines must succeed** | M3：品質關卡 |
| 把密碼安全地交給 CI | Settings → CI/CD → Variables（**Masked**、**Protected**） | M2：機密不進 repo |
| 打版本 tag、image 多掛一個版本名 | Code → Tags；Deploy → Container registry | M3：版本號控管 |
| 下載這一版的產物、寫發版紀錄 | job 的 **Job artifacts**；Deploy → Releases | M3：Release Artifacts |

部署到 dev／qa／poc 三個環境、一鍵 Rollback，接在這份後面：[03b-gitlab-environments-release.md](03b-gitlab-environments-release.md)。

---

## 開始前

- **公司已經有 GitLab**（例如 `https://gitlab.你們公司.com`）：跳過 Part 0，直接從 [Part 1](#part-1登入建專案推程式) 開始。文件裡的 `http://gitlab:8929` 換成公司的網址，`student` 換成你的帳號。
- **沒有 GitLab**：照 Part 0 在自己電腦上架一台（約 30 分鐘，大部分時間在等它開機）。
- 範例程式在學員 zip 解壓後的 **`ci-sample-repo/`** 資料夾（跟 `assets/`、`docs/` 放在一起）。它就是一個 .NET API ＋前端的小專案，**沒有** `.gitlab-ci.yml`——pipeline 由你在 Part 3 自己加。
- 每一步的格式：**操作** → 截圖 → **你應該看到** → **如果不是這樣** → **為什麼**（不是每步都需要全部五項）。

---

## Part 0：自己架一台 GitLab（公司已有 GitLab 的人跳到 Part 1）

### 步驟 0-1：給 Docker 足夠的記憶體

**操作**：打開 Docker Desktop → 右上齒輪 **Settings** → **Resources** → **Memory**，拉到 **6 GB 以上**（電腦總共 16 GB 的話，8 GB 最舒服）→ **Apply & restart**。

**為什麼**：GitLab 一個容器開起來就吃約 3–4 GB（講師電腦實測 3.2 GB），pipeline 跑 .NET 編譯時還要再加 1–2 GB。記憶體不夠，GitLab 會一直重開或網頁 502。

> Windows 用 WSL 2 後端的 Docker Desktop，Memory 設定可能不在畫面上，要改 `%UserProfile%\.wslconfig` 的 `memory=6GB`，存檔後 `wsl --shutdown` 再開 Docker Desktop。

### 步驟 0-2：建一個資料夾，放 `docker-compose.yml`

**操作**：建一個新資料夾（例如桌面上的 `gitlab-lab`），在裡面新增檔案 `docker-compose.yml`，內容如下：

```yaml
# 自己電腦上的練習用 GitLab＋Runner（只給自己練習，不要開放給別人連）
services:
  gitlab:
    image: gitlab/gitlab-ce:19.4.3-ce.0
    hostname: gitlab
    environment:
      GITLAB_ROOT_PASSWORD: "Change-Me-2026!"   # root 的密碼，改成你自己的（至少 8 字元，不要用常見密碼）
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://gitlab:8929'
        registry_external_url 'http://gitlab:5050'
        gitlab_rails['gitlab_shell_ssh_port'] = 2224
        puma['worker_processes'] = 0
        sidekiq['concurrency'] = 5
        prometheus_monitoring['enable'] = false
        gitlab_rails['usage_ping_enabled'] = false
        gitlab_kas['enable'] = false
    ports:
      - "8929:8929"
      - "5050:5050"
    shm_size: 256m
    volumes:
      - gitlab-config:/etc/gitlab
      - gitlab-logs:/var/log/gitlab
      - gitlab-data:/var/opt/gitlab

  runner:
    image: gitlab/gitlab-runner:alpine-v19.4.1
    volumes:
      - runner-config:/etc/gitlab-runner
      - /var/run/docker.sock:/var/run/docker.sock

volumes:
  gitlab-config:
  gitlab-logs:
  gitlab-data:
  runner-config:

networks:
  default:
    name: ci-demo
```

**每一行在做什麼**：

| 設定 | 意思 |
|------|------|
| `image: gitlab/gitlab-ce:19.4.3-ce.0` | GitLab 社群版（免費），**寫死版本**，跟本文件截圖同一版。不要寫 `latest`——哪天自動升版，畫面就跟文件對不上 |
| `hostname: gitlab` | 容器的主機名。同一個 compose 裡的 Runner 用 `gitlab` 這個名字找到它 |
| `GITLAB_ROOT_PASSWORD` | 第一次開機時設定管理員 `root` 的密碼。**只有第一次開機有效**，之後改這行不會改到密碼 |
| `external_url 'http://gitlab:8929'` | GitLab 認為自己的網址。畫面上所有連結、clone 網址都用它產生；GitLab 也會照這個 port（8929）開網頁服務 |
| `registry_external_url 'http://gitlab:5050'` | 開啟 **Container Registry**（放 docker image 的倉庫），在 5050 port |
| `gitlab_shell_ssh_port = 2224` | 畫面上顯示的 SSH clone 網址用 2224 port（不跟你電腦自己的 SSH 22 port 打架）。本文件全程用 HTTPS（帳號＋token）推程式，所以 compose 沒有開放 2224；想用 SSH 再在 `ports` 加一行 `- "2224:22"` |
| `puma['worker_processes'] = 0` | 網頁伺服器只開一個行程，省約 1 GB 記憶體。一個人用夠了 |
| `sidekiq['concurrency'] = 5` | 背景工作（寄信、跑 pipeline 排程）同時處理 5 件，預設 20，同樣是省記憶體 |
| `prometheus_monitoring`、`usage_ping`、`gitlab_kas` 設 `false` | 關掉內建監控、使用統計回報、Kubernetes agent 服務。練習用不到，關掉省資源 |
| `ports` | 8929 給瀏覽器和 git，5050 給 docker image |
| `shm_size: 256m` | 給 GitLab 內建的 PostgreSQL 多一點共享記憶體（Docker 預設 64 MB 太小，會出現奇怪的資料庫錯誤） |
| `volumes`（gitlab） | 設定、log、資料（repo、資料庫）都存在 Docker volume。容器砍掉重建，資料還在 |
| `runner` 服務 | **GitLab Runner**：真正執行 pipeline 的程式。它本身不編譯，而是每個 job 開一個新容器去跑 |
| `/var/run/docker.sock` | 讓 Runner 能叫你電腦上的 Docker 開 job 容器。Windows／Mac 的 Docker Desktop 也是寫這個路徑 |
| `networks: default: name: ci-demo` | 給這組容器的網路一個固定名字。Part 2 註冊 Runner 時會用到：job 容器也要接到這個網路，才找得到 `gitlab` |

### 步驟 0-3：啟動

**操作**：終端機進到 `gitlab-lab` 資料夾：

```bash
docker compose up -d
```

第一次會下載 GitLab image（約 1.5 GB）。下載完 GitLab 還要初始化資料庫，**第一次開機大約 5–10 分鐘**。每隔一兩分鐘看一次狀態：

```bash
docker compose ps
```

![docker compose ps：gitlab 的 STATUS 出現 (healthy)](images/gitlab0/001-term-compose-ps.png)

**你應該看到**：`gitlab` 那行的 STATUS 是 **`Up … (healthy)`**；`runner` 是 `Up`（Runner 沒有健康檢查，不會顯示 healthy）。

**如果不是這樣**：
- 顯示 `(health: starting)`：還在開機，繼續等。
- 超過 15 分鐘還不是 healthy，或 STATUS 是 `Restarting`：多半是記憶體不夠，回步驟 0-1 調大。看原因：`docker compose logs gitlab --tail 50`。
- `port is already allocated`：8929 或 5050 被別的程式佔了。

想確認 GitLab 裡面每個服務都起來了：

```bash
docker compose exec gitlab gitlab-ctl status
```

![gitlab-ctl status：每個服務都是 run:；curl 登入頁回 200](images/gitlab0/002-term-gitlab-ctl.png)

**你應該看到**：每行開頭都是 `run:`（puma 是網頁、sidekiq 是背景工作、postgresql 是資料庫、registry 是 image 倉庫）。

### 步驟 0-4：讓電腦認得 `gitlab` 這個名字

GitLab 產生的連結都是 `http://gitlab:8929/...`，你的電腦要知道 `gitlab` 就是自己。在 **hosts 檔**最後加一行：

```
127.0.0.1 gitlab
```

- **macOS／Linux**：

  ```bash
  echo "127.0.0.1 gitlab" | sudo tee -a /etc/hosts
  ```

- **Windows**：開始功能表搜尋「記事本」→ 右鍵 **以系統管理員身分執行** → 檔案 → 開啟 `C:\Windows\System32\drivers\etc\hosts`（右下角檔案類型選「所有檔案」才看得到）→ 最後加上那一行 → 存檔。

**如果不是這樣**：Windows 存檔時說「沒有權限」＝記事本不是用系統管理員身分開的。

### 步驟 0-5：用 root 登入

**操作**：瀏覽器打開 **http://gitlab:8929**。

![GitLab 登入頁](images/gitlab0/003-signin.png)

**你應該看到**：GitLab Community Edition 登入頁。

**如果不是這樣**：
- 「找不到伺服器」：hosts 沒加好（步驟 0-4）。先試 http://localhost:8929 ，打得開就是 hosts 的問題。
- **502** 頁面：GitLab 還沒開完機，等幾分鐘再重新整理。

**Username** 填 `root`，**Password** 填 compose 裡 `GITLAB_ROOT_PASSWORD` 的值 → **Sign in**。

![填好 root 和密碼](images/gitlab0/004-signin-filled.png)

**如果密碼不對**：
- 你當初沒設 `GITLAB_ROOT_PASSWORD`：GitLab 會自己產生一組，用這行看：

  ```bash
  docker compose exec gitlab cat /etc/gitlab/initial_root_password
  ```

  這個檔案**只有沒設 `GITLAB_ROOT_PASSWORD` 時才會產生**，而且**開機 24 小時後自動刪除**。
- 你設的密碼太簡單（例如 `password123`）：GitLab 會拒絕，root 就沒有密碼。最快的辦法是全部重來：`docker compose down -v`（**會刪掉所有資料**），改一個強一點的密碼，再 `docker compose up -d`。

### 步驟 0-6：跳過「建立第一個專案」

![root 第一次登入：Create your first project](images/gitlab0/005-root-home.png)

**你應該看到**：「Create your first project」，要你填 Group name、Project name。

**操作**：按 **Skip**。專案等一下用學員帳號建，不要用 root 建。

**為什麼**：root 是**管理員**，權限大到可以改整台 GitLab 的設定。日常工作用一般帳號，跟 Linux 不用 root 寫程式是同一個道理；在公司 GitLab 上你拿到的也是一般帳號。

### 步驟 0-7：建一個一般帳號

**操作**：右上角 **Admin** 按鈕（扳手圖示）進入 **Admin area** → 左側 **Users** → 右上 **New user**。

![Admin area → Users，右上 New user](images/gitlab0/006-admin-users.png)

填 **Name** `Lab Student`、**Username** `student`、**Email** `student@example.com`（練習用，不會真的寄信）→ 拉到最下面按 **Create user**。

![New user 表單](images/gitlab0/007-admin-new-user-filled.png)

**你應該看到**：Lab Student 的帳號頁。

![帳號建好了](images/gitlab0/008-admin-user-created.png)

Password 區塊寫著「Reset link will be generated and sent to the user」——要寄信重設密碼。我們這台沒有寄信功能，所以改成**管理員直接給一組臨時密碼**：

**操作**：右上 **Edit** → **Password** 和 **Password confirmation** 填同一組臨時密碼（例如 `Temp-Pass-2026!`）→ 最下面 **Save changes**。

![Edit：設定臨時密碼](images/gitlab0/009-admin-user-edit-password.png)

**為什麼是「臨時」**：管理員設的密碼，學員第一次登入時 GitLab 會**強制要求改掉**（下一步會看到）。管理員不該知道別人的密碼。

最後右上角大頭貼 → **Sign out**，登出 root。

---

## Part 1：登入、建專案、推程式

> 用公司 GitLab 的人從這裡開始：用公司給你的帳號登入，下面「改密碼」那步不一定會出現。

### 步驟 1-1：學員第一次登入，改密碼

**操作**：用 `student`／臨時密碼登入。

![Update password for Lab Student](images/gitlab0/010-student-new-password-filled.png)

**你應該看到**：「Update password for Lab Student」。**Current password** 填臨時密碼，**New password**、**Confirm password** 填你自己的新密碼 → **Update password**。

**你應該看到**：回到登入頁（改完密碼要重新登入）。

![改完密碼回到登入頁](images/gitlab0/011-student-after-change.png)

用新密碼再登入一次。

![學員首頁 Your work → Home](images/gitlab0/012-student-home.png)

**你應該看到**：左上 **Your work**，中間是 Lab Student 的首頁，各種計數都是 0。

### 步驟 1-2：建一個空專案

**操作**：頂端 **+**（New）→ **New project/repository**。

![+ 選單：New project/repository](images/gitlab0/013-new-menu.png)

選 **Create blank project**（不要選 Create from template、Import project）。

![Create new project：選 Create blank project](images/gitlab0/014-new-project-choose.png)

填表：

1. **Project name**：`deploylog`（Project slug 會自動跟著填）。
2. **Project URL** 右邊的下拉選單 **Select a group or namespace**：**一定要選**，選 `student`（你自己的帳號）。

   ![Project URL 要選 namespace：Users → student](images/gitlab0/015-new-project-namespace.png)

3. **Visibility Level**：維持 **Private**。
4. **Project Configuration**：**取消勾選 Initialize repository with a README**（預設是勾的，上一張圖就是勾著的狀態）。
5. 按 **Create project**。

![填好的樣子：namespace 是 student、README 沒勾](images/gitlab0/016-new-project-form.png)

**如果不是這樣**：
- 按 Create project 沒反應、欄位出現紅字：namespace 沒選。
- 勾了 README 也建好了：專案裡已經有一個 commit，等一下 push 會被拒絕（`rejected … fetch first`）。最簡單的處理是刪掉專案重建：Settings → General → 最下面 Advanced → Delete project。

**為什麼不要 README**：我們要把**已經存在的資料夾**（`ci-sample-repo`）推上來。遠端如果先有一個 README commit，兩邊的歷史對不上，就得先 pull 合併，多一道手續。

![空專案頁，Add files 切到 HTTPS](images/gitlab0/017-empty-project-push.png)

**你應該看到**：「The repository for this project is empty」，下面是 **Command line instructions**。**Add files** 那裡切到 **HTTPS** 分頁，往下捲會看到 **Push an existing folder**——下一步要做的就是這個。

### 步驟 1-3：建一把 Personal access token（給 git 用的密碼）

GitLab 的 HTTPS push **不收登入密碼**，要用 **Personal access token**（PAT）。

**操作**：右上角大頭貼 → **Edit profile**。

![大頭貼選單：Edit profile](images/gitlab0/018-avatar-menu.png)

左側 **Access** → **Personal access tokens**。

![User settings → Access](images/gitlab0/019-profile-access-menu.png)

![Personal access tokens 頁，目前 0 個](images/gitlab0/020-pat-list.png)

右邊 **Generate token** 下拉 → 選 **Legacy token**。

![Generate token：Fine-grained token／Legacy token](images/gitlab0/021-pat-generate-menu.png)

填表：

- **Token name**：`laptop-git`（看名字就知道這把是哪台電腦在用）
- **Description**：`在自己電腦上 git clone / push 用`
- **Expiration date**：保留預設（約一個月後到期）
- **Select scopes**：只勾 **read_repository** 和 **write_repository**

![Generate legacy token 表單](images/gitlab0/022-pat-form.png)

![Scopes 只勾 read_repository、write_repository](images/gitlab0/023-pat-form-scopes.png)

拉到最下面按 **Generate token**。

![Your new token has been created](images/gitlab0/024-pat-created.png)

**你應該看到**：「Your new token has been created」。按右邊的**複製**圖示，把 token 貼到記事本暫存。

> ⚠️ **這個畫面離開就再也看不到 token。** 忘了複製就只能刪掉重建一把。

**為什麼這樣選**：
- **只勾 repository 兩個 scope**：這把 token 只能讀寫程式碼，就算外洩，也不能拿去改你的帳號設定或呼叫 API 做別的事。**最小權限**——跟 M2 講的 DB 帳號只給需要的權限是同一件事。
- **會過期**：忘了撤銷的 token 不會永遠有效。
- **Fine-grained token** 可以把權限縮到單一專案，更安全；但目前 git push 要用的權限選起來比較繁瑣，練習先用 Legacy token。

### 步驟 1-4：把範例程式推上去

**操作**：終端機進到學員 zip 解壓出來的 `ci-sample-repo` 資料夾，照順序打：

```bash
cd ci-sample-repo
git init --initial-branch=main
git config --local user.name "Lab Student"
git config --local user.email "student@example.com"
git remote add origin http://localhost:8929/student/deploylog.git
git add .
git commit -m "Initial commit"
git push --set-upstream origin main
```

問 **Username** 填 `student`；問 **Password** **貼上剛剛的 token**（貼上時畫面不會顯示任何字，直接按 Enter）。

![git push 的完整過程](images/gitlab0/025-term-push.png)

**你應該看到**：最後幾行是 `* [new branch] main -> main` 和 `branch 'main' set up to track 'origin/main'.`

**如果不是這樣**：
- `HTTP Basic: Access denied`：Password 貼的是登入密碼而不是 token，或 token 沒勾 `write_repository`。
- `rejected … (fetch first)`：建專案時勾了 README（見步驟 1-2）。
- Windows 跳出 **Git Credential Manager** 視窗：一樣帳號填 `student`、密碼貼 token。之後它會記住，不用每次輸入。
- 用公司 GitLab：`remote add` 的網址換成專案頁 **Code** 按鈕裡 **Clone with HTTP** 的網址。

**為什麼網址用 `localhost`**：畫面上顯示的是 `http://gitlab:8929/...`（來自 `external_url`）。加了 hosts 之後兩個都通，都是你自己的電腦；用 `localhost` 的好處是就算 hosts 沒設好也推得上去。`git config --local` 只設定**這個 repo** 的作者名字，不影響你電腦上其他專案。

回到瀏覽器，重新整理專案頁：

![專案頁出現檔案](images/gitlab0/026-repo-page.png)

**你應該看到**：`frontend`、`src/Api`、`tests/Api.Tests`、`Dockerfile` 等檔案，最上面是 Initial commit。

> ⚠️ **注意那個紅色叉叉（或轉圈圈）**：你還沒寫任何 pipeline，GitLab 卻跑了一條，而且失敗了。右側 Project information 寫著 **Auto DevOps enabled**——見下一節。

![Initial commit 旁邊是紅色叉叉](images/gitlab0/027-sidebar-build.png)

**為什麼會這樣（Auto DevOps 的陷阱）**：專案裡**沒有** `.gitlab-ci.yml` 時，GitLab 預設會套用 **Auto DevOps**，自己猜要怎麼 build、test、做程式碼品質掃描。它猜不到我們專案的結構，所以 build／test／code_quality 都失敗。**不用理它**：Part 3 加了 `.gitlab-ci.yml` 之後，GitLab 就只照你的檔案跑，Auto DevOps 不會再出現。想直接關掉：Settings → CI/CD → **Auto DevOps** → 取消勾選 **Default to Auto DevOps pipeline** → Save changes。

以後在別台電腦要 clone 這個專案，網址在專案頁的 **Code** 按鈕裡：

![Code 按鈕：Clone with SSH（port 2224）／Clone with HTTP](images/gitlab0/028-code-dropdown.png)

（這張是做完整份文件後拍的，所以檔案比你現在多一個 `.gitlab-ci.yml`。）**Clone with SSH** 的網址有 `:2224`，就是 compose 裡 `gitlab_shell_ssh_port` 那行的效果。

---

## Part 2：註冊 Runner

Pipeline 寫好了也要有**人**來跑。GitLab 本身只負責排程和顯示結果，真正執行 job 的是 **Runner**。

> **公司 GitLab**：通常管理員已經準備好共用的 **Instance runners**，你看得到就可以**跳過 Part 2**（而且**不要**做步驟 2-2 的「關掉 instance runners」）。看不到、或公司規定每個專案自己帶 Runner，再找管理員討論。

### 步驟 2-1：找到 Runners 設定

**操作**：專案左側 **Settings** → **CI/CD**。

![Settings → CI/CD：一排可以展開的區塊](images/gitlab0/029-settings-cicd.png)

**Runners** 那區按 **Expand**（或點標題）。

![Runners 展開：Assigned project runners 是空的](images/gitlab0/030-runners-section.png)

**你應該看到**：**Available Runners** 下有四個分頁：**Assigned project runners**、**Other available project runners**、**Group**、**Instance**。目前「No project runners found」。

### 步驟 2-2：關掉 instance runners（只用自己的）

**操作**：點 **Instance** 分頁。

![Instance 分頁：Turn on instance runners for this project 是開的](images/gitlab0/031-runners-instance-tab.png)

**你應該看到**：**Turn on instance runners for this project** 開關。截圖這台是講師的 GitLab，所以下面列了兩台 instance runner；你自己架的 GitLab 這裡是空的。

**操作**：把開關**關掉**。

![Instance runners are turned off](images/gitlab0/032-runners-instance-off.png)

**為什麼**：Instance runner 是整台 GitLab 共用的。關掉之後，這個專案的 job **只會**交給你等一下註冊的 project runner，job log 裡看得到是哪台跑的，比較好除錯。

### 步驟 2-3：在畫面上建立 project runner

**操作**：右上 **Create project runner**。

![Create project runner 空表單](images/gitlab0/033-new-runner-form.png)

- **Tags**：留空
- 勾 **Run untagged jobs**
- **Runner description**：`student-runner`
- 其他都不動，拉到最下面按 **Create runner**

![填好的樣子](images/gitlab0/034-new-runner-filled.png)

**為什麼勾 Run untagged jobs**：我們的 `.gitlab-ci.yml` 沒有替 job 加 `tags:`。沒勾的話，這台 Runner 只接「有對應 tag」的 job，pipeline 會一直卡在 pending。

![Register "student-runner" runner：Step 1 有一段指令](images/gitlab0/035-runner-register-page.png)

**你應該看到**：「Register "student-runner" runner」，**Step 1** 有一段 `gitlab-runner register --url http://gitlab:8929 --token glrt-…`。

> ⚠️ **`glrt-` 開頭的 token 只會在這個頁面顯示一次**，而且它能把任何機器註冊成你專案的 Runner。不要貼到聊天群組或 commit 進 repo。

### 步驟 2-4：在終端機註冊

畫面給的指令是「互動式」的，會一題一題問。我們直接把答案都寫在指令裡。**在 `docker-compose.yml` 所在的資料夾**（`gitlab-lab`）執行，`--token` 換成**你畫面上的 token**：

```bash
docker compose exec runner gitlab-runner register --non-interactive \
  --url http://gitlab:8929 --clone-url http://gitlab:8929 \
  --token glrt-換成你畫面上的token \
  --executor docker --docker-image alpine:3.20 --docker-privileged \
  --docker-network-mode ci-demo --docker-volumes /certs/client \
  --docker-pull-policy if-not-present
```

Windows PowerShell 把每行結尾的 `\` 換成 `` ` ``（反引號），或全部接成一行。

![register 成功：Runner registered successfully](images/gitlab0/036-term-register.png)

**你應該看到**：`Verifying runner... is valid` 和 `Runner registered successfully`。設定存進 Runner 容器裡的 `/etc/gitlab-runner/config.toml`，Runner 會自動重新載入，不用重開。

**每個參數在做什麼**：

| 參數 | 意思 |
|------|------|
| `docker compose exec runner` | 在 Runner 容器裡執行（你的電腦不用另外安裝 gitlab-runner） |
| `--url http://gitlab:8929` | GitLab 在哪裡。Runner 容器跟 GitLab 在同一個 compose 網路，直接用 `gitlab` 這個名字 |
| `--clone-url http://gitlab:8929` | job 容器 `git clone` 程式碼時用的網址 |
| `--executor docker` | 每個 job 開一個**全新的容器**來跑，跑完就丟。這就是「不靠某個人的電腦」：每次都從乾淨環境開始 |
| `--docker-image alpine:3.20` | job 沒寫 `image:` 時用的預設 image |
| `--docker-privileged` | `docker-build` job 要在容器裡再跑 Docker（Docker-in-Docker，dind），需要特權模式 |
| `--docker-network-mode ci-demo` | job 容器接到 compose 的 `ci-demo` 網路，才找得到 `gitlab`（clone 程式、推 image 到 `gitlab:5050`） |
| `--docker-volumes /certs/client` | dind 產生的 TLS 憑證放這裡，讓 job 和 dind 服務共用 |
| `--docker-pull-policy if-not-present` | 本機已經有的 image 就不重新下載。.NET SDK image 將近 1 GB，每個 job 都重下會很慢 |

**如果不是這樣**：
- `no such service: runner`：不在 `docker-compose.yml` 那個資料夾。
- `401 Unauthorized` 或 `invalid token`：token 複製不完整，或這個 token 已經用過了。回 Runners 頁把那台刪掉，重新 Create project runner。

### 步驟 2-5：確認 Runner 上線

回到瀏覽器，Settings → CI/CD → Runners。

![Assigned project runners：#11 student-runner，Online](images/gitlab0/037-runner-online.png)

**你應該看到**：**Assigned project runners** 有一台 `student-runner`，狀態 **Online**、**Idle**（在線、閒著）。

**如果不是這樣**：顯示 **Never contacted** 或灰色：等 30 秒重新整理。還是不行就看 `docker compose logs runner --tail 30`。

---

## Part 3：寫第一條 pipeline

### 步驟 3-1：打開 Pipeline editor

**操作**：左側 **Build** → **Pipeline editor**。

![Pipeline editor 還沒有設定檔：Start building](images/gitlab0/038-editor-empty.png)

**你應該看到**：「Get up and running with GitLab CI/CD」，兩個選項：**Use a CI/CD component**（用別人寫好的元件）和 **Write your own**（自己寫）。

**操作**：**Write your own** 下面的 **Start building**。

![編輯器出現一份範本](images/gitlab0/039-editor-template.png)

**你應該看到**：編輯器裡已經有一份 GitLab 的範例 `.gitlab-ci.yml`（build-job、unit-test-job…）。

### 步驟 3-2：貼上課程的 pipeline

**操作**：

1. 用編輯器打開學員 zip 裡的 **`assets/gitlab-ci-dotnet-example.yml`**（就是 M3 Part A 一行一行讀過的那份），全選複製。
2. 回到 Pipeline editor，**全選刪掉範本**，貼上。
3. 做下面**兩處修改**：

**修改 1**：找到 `docker-build` job 的 `services:`，把

```yaml
  services:
    - docker:27-dind
```

改成

```yaml
  services:
    - name: docker:27-dind
      # 只有自架、沒有 TLS 的 registry 才需要這行（公司 GitLab 的 registry 有 HTTPS 就拿掉）
      command: ["--insecure-registry=gitlab:5050"]
```

**為什麼**：Part 0 架的 registry 是 `http://`（沒有 TLS 憑證），Docker 預設拒絕把 image 推到不安全的 registry。這行告訴 dind「`gitlab:5050` 是自己人，允許用 http」。公司 GitLab 的 registry 有 HTTPS，**不要**加這行。

**修改 2**：在檔案**最後面**加一個練習用的 job（Part 5 用來看 Masked／Protected 的效果）：

```yaml

# 【練習用】印出 CI/CD 變數，看 Masked／Protected 的效果（Settings → CI/CD → Variables）
secrets-demo:
  stage: test
  image: alpine:3.20
  script:
    - echo "部署帳號：${DEPLOY_USER}"
    - echo "部署密碼：${DEPLOY_PASSWORD}"
    - 'if [ -z "${PROD_DB_PASSWORD}" ]; then echo "這個分支拿不到 PROD_DB_PASSWORD（Protected）"; else echo "PROD_DB_PASSWORD 已注入：${PROD_DB_PASSWORD}"; fi'
```

![貼好之後：上方 Pipeline syntax is correct](images/gitlab0/040-editor-pasted.png)

**你應該看到**：編輯器上方綠色勾勾 **Pipeline syntax is correct**。

**如果不是這樣**：出現紅色 **This GitLab CI configuration is invalid**，通常是縮排亂了。YAML 用**空白**縮排、不能有 Tab。整份重新貼一次，修改時注意 `- name:` 和下一行 `command:` 的對齊。

### 步驟 3-3：Visualize：看 job 的順序

**操作**：編輯器上方 **Visualize** 分頁。

![Visualize：build 2 個、test 2 個、package 1 個、docker 1 個](images/gitlab0/041-editor-visualize.png)

**你應該看到**：四欄 stage——**build**（build、build-frontend）、**test**（secrets-demo、test）、**package**（publish）、**docker**（docker-build）。

**為什麼**：同一欄的 job **同時**跑；前一欄**全部成功**，下一欄才會開始。所以測試沒過，publish 和 docker-build 根本不會跑——這就是 CI 的品質關卡。

### 步驟 3-4：Validate：模擬跑一次

**操作**：**Validate** 分頁 → **Validate pipeline**。

![Validate：Simulation completed successfully](images/gitlab0/042-editor-validate.png)

**你應該看到**：**Simulation completed successfully**，下面列出每個 job 會執行的指令。

**為什麼**：Syntax correct 只代表 YAML 格式對；Validate 會模擬「push 到 main」時 `rules:` 怎麼判斷、哪些 job 會跑。這一步什麼都不會真的執行。

### 步驟 3-5：Commit

**操作**：回到 **Edit** 分頁，往下捲到 commit 區：

- **Commit message**：`Add CI pipeline: build → test → package → docker`
- **Branch**：`main`
- 按 **Commit changes**

![填 commit message](images/gitlab0/043-editor-commit-form.png)

![Commit 完成，pipeline 開始跑](images/gitlab0/044-editor-committed.png)

**你應該看到**：編輯器上方出現 **Pipeline running for b72c5e86**（你的 commit 編號會不一樣），旁邊四個圓點是四個 stage 的進度。這次 commit 就是在 repo 根目錄新增 `.gitlab-ci.yml`。

![專案頁多了 .gitlab-ci.yml，最新 commit 旁邊是綠勾](images/gitlab0/045-repo-with-ci.png)

### 步驟 3-6：看 pipeline 跑完

**操作**：左側 **Build** → **Pipelines**。

![Pipelines 列表：#26 Passed、#25 Failed](images/gitlab0/046-pipelines-list-1.png)

**你應該看到**：最上面一條 **Passed**（綠色），下面一條 **Failed**——那是 Part 1 的 Auto DevOps 失敗的那條。

**如果不是這樣**：
- 一直是 **Pending**、「This job is stuck」：沒有 Runner 接（Part 2 沒做完，或 Run untagged jobs 沒勾）。
- **第一次跑很久**：Runner 要下載 .NET SDK（約 1 GB）、Node.js、Docker image，可能 5–10 分鐘；之後同一台電腦就快了（講師電腦第二次約 1 分鐘）。
- `docker-build` 紅燈、log 有 `http: server gave HTTP response to HTTPS client`：步驟 3-2 的修改 1 沒做。

**操作**：點 pipeline 編號（`#26`）。

![Pipeline 圖：四個 stage 都是綠勾；Jobs 6、Tests 3](images/gitlab0/047-pipeline-graph-1.png)

**你應該看到**：四欄、六個 job 都是綠勾；上方分頁 **Jobs 6**、**Tests 3**。

**操作**：點 `test` 那個 job。

![test job 的 log：Passed! Total: 3](images/gitlab0/048-job-test-log.png)

**你應該看到**：黑底的 job log，`Passed! - Failed: 0, Passed: 3, Skipped: 0, Total: 3`，最後 `Job succeeded`。右側 **Runner** 寫 `#11 (…) student-runner`——就是你註冊的那台。

**為什麼要會看 log**：pipeline 紅了，第一件事永遠是**點進紅色那個 job 看 log 最後幾行**。錯誤訊息都在那裡。

---

## Part 4：測試失敗，合併被擋下來

這一段故意把測試改壞，看 GitLab 怎麼阻止壞掉的程式碼進 main。

### 步驟 4-1：在網頁上改一個測試

**操作**：專案頁點進 `tests` → `Api.Tests` → `RequiredSettingsTests.cs`。

![RequiredSettingsTests.cs](images/gitlab0/049-file-view.png)

右上 **Edit** → **Edit single file**。

![Edit 選單：Open in Web IDE／Edit single file](images/gitlab0/050-file-edit-menu.png)

找到第 16 行：

```csharp
Assert.Empty(RequiredSettings.Missing(config));
```

改成：

```csharp
Assert.Equal(["DB_NAME"], RequiredSettings.Missing(config));  // 故意寫錯的預期值
```

![改好第 16 行](images/gitlab0/051-file-edited.png)

**為什麼這樣改**：這個測試的意思是「設定都給齊了，就不該回報缺少任何設定」。改成「應該缺 DB_NAME」，等於寫了一個錯的預期值，測試一定失敗。

### 步驟 4-2：commit 到新分支，順便開 Merge request

**操作**：右上 **Commit changes**，跳出視窗：

- **Commit message**：`改了測試的預期值（練習：測試沒過，後面的 stage 不會跑）`
- **Branch**：選 **Commit to a new branch**，分支名稱 `feature/break-test`
- 勾 **Create a merge request for this change**
- 按 **Commit changes**

![Commit changes 視窗](images/gitlab0/052-commit-modal.png)

**為什麼開新分支**：不直接改 main。改動先放在自己的分支，透過 **Merge request**（MR，合併請求）讓別人審、讓 pipeline 驗證，過了才進 main。

**你應該看到**：New merge request 頁，From `feature/break-test` into `main`，Title 已經帶入 commit message。

![New merge request](images/gitlab0/053-new-mr-form.png)

往下捲，其他欄位不用動，按 **Create merge request**。

![New merge request 下半部：Create merge request](images/gitlab0/054-new-mr-form-bottom.png)

![MR !1 建好了，pipeline 還在跑](images/gitlab0/055-mr-created.png)

**你應該看到**：MR 頁，標題下面 **Open**。中間一開始是「Checking pipeline status」。

### 步驟 4-3：看 MR 上的失敗

等一兩分鐘，重新整理。

![MR：Pipeline #27 failed；Test summary: 1 failed, 3 total tests](images/gitlab0/056-mr-failed.png)

**你應該看到**：
- **Pipeline #27 failed**（紅色叉叉）
- **Test summary: 1 failed, 3 total tests**

**注意**：下面竟然還寫著 **Ready to merge!**，**Merge** 按鈕是可以按的。GitLab 預設**不擋**——步驟 4-5 會把它擋起來。

**操作**：Test summary 那行右邊的展開箭頭。

![Test summary 展開：NothingMissing_WhenAllSet 失敗](images/gitlab0/057-mr-test-summary.png)

**你應該看到**：失敗的是 `NothingMissing_WhenAllSet`——就是你改的那個測試。**不用翻 log 就知道哪個測試壞了**，這是 `test` job 輸出 JUnit 報告（`reports: junit:`）的效果。

**操作**：MR 上方 **Pipelines** 分頁。

![MR 的 Pipelines 分頁](images/gitlab0/058-mr-pipelines-tab.png)

點進 pipeline `#27`：

![Pipeline #27：test 紅、publish 沒跑](images/gitlab0/059-pipeline-red.png)

**你應該看到**：build 綠、**test 紅**、secrets-demo 綠、**package（publish）灰色沒跑**。這條是 feature 分支，所以本來就沒有 docker stage（`docker-build` 的 `rules:` 只在 main 和 tag 跑）。

**為什麼**：測試失敗，後面的打包就不做——壞掉的版本不會變成產物，更不會變成 image。

### 步驟 4-4：Tests 分頁和失敗的 log

**操作**：pipeline 上方 **Tests** 分頁。

![Tests 分頁 Summary：3 tests、1 failures、66.67% success rate](images/gitlab0/060-tests-tab.png)

**你應該看到**：**Summary** 寫 3 tests、1 failures、0 errors、**66.67% success rate**；下面 **Jobs** 表格列出 `test` 這個 job：Failed 1、Passed 2、Total 3。

**操作**：點 `test` 那一列，看每一個測試：

![test 裡每個測試的結果，失敗的排最前面](images/gitlab0/061-tests-tab-suite.png)

回 **Jobs**，點紅色的 `test` job：

![test job log：Failed!](images/gitlab0/062-job-test-failed.png)

**你應該看到**：log 裡 `NothingMissing_WhenAllSet [FAIL]`、`Assert.Equal() Failure: Collections differ`，`Expected: ["DB_NAME"]`、`Actual: []`，還指出是 `RequiredSettingsTests.cs:line 16`；接著 `Failed! - Failed: 1, Passed: 2, Skipped: 0, Total: 3`。右側 **Test summary: 1 of 3 failed**。

### 步驟 4-5：設定「pipeline 沒過不准合併」

**操作**：左側 **Settings** → **Merge requests** → 往下找 **Merge checks** → 勾 **Pipelines must succeed** → 這一區最下面 **Save changes**。

![Merge checks：勾 Pipelines must succeed](images/gitlab0/063-mr-setting-pipelines-succeed.png)

回到 MR !1 重新整理：

![Merge blocked: 1 check failed — Pipeline must succeed](images/gitlab0/064-mr-blocked.png)

**你應該看到**：**Merge blocked: 1 check failed**，原因 **Pipeline must succeed**。Merge 按鈕不見了。

**為什麼**：CI 的價值在於「**紅燈就停**」。如果紅燈還能合併，大家很快就會習慣忽略它。這個勾一打，規則就從「請大家自律」變成「系統擋住」。

> 這個 MR **不要合併**，留著讓它開著就好。後面的步驟都在 main 上做。

---

## Part 5：把密碼交給 CI（Masked／Protected）

M2 講過：密碼不寫進 repo。到了 CI，密碼放在 GitLab 的 **CI/CD Variables**，job 執行時才注入成環境變數。

### 步驟 5-1：打開 Variables

**操作**：**Settings** → **CI/CD** → **Variables** 展開。

![Variables：There are no variables yet](images/gitlab0/065-variables-empty.png)

**操作**：**Add variable**。

![Add variable 抽屜（預設值）](images/gitlab0/066-variable-drawer-empty.png)

**你應該看到**：右邊滑出 **Add variable**。注意 GitLab 19.4 的**預設值**：**Visibility** 預設選 **Masked**、**Protect variable** 預設**勾著**。下面每個變數都要照表調整，不要直接用預設。

我們加三個變數，各代表一種等級：

| Key | Value | Visibility | Protect variable | 代表什麼 |
|-----|-------|------------|------------------|---------|
| `DEPLOY_USER` | `deployer` | **Visible** | **不勾** | 不是秘密的設定，看得到也沒關係 |
| `DEPLOY_PASSWORD` | `Dep10y-Pa55w0rd` | **Masked** | **不勾** | 秘密，log 裡要遮掉 |
| `PROD_DB_PASSWORD` | `Pr0d-Db-Secret-2026` | **Masked** | **勾** | 正式環境的秘密，只有受保護的分支／tag 拿得到 |

（Value 是練習用的假密碼。）

### 步驟 5-2：加 `DEPLOY_USER`（Visible、不保護）

**操作**：抽屜上半部 **Visibility** 選 **Visible**；**Flags** 的 **Protect variable** **取消勾選**。

![上半部：Visible、Protect variable 不勾](images/gitlab0/067-variable-drawer-visible-top.png)

（這張上半部是事後按 ✏️ 開的 **Edit variable** 抽屜，欄位跟 Add variable 一樣。）

往下捲：**Key** `DEPLOY_USER`、**Value** `deployer` → **Add variable**。

![下半部：Key、Value，按 Add variable](images/gitlab0/068-variable-drawer-visible.png)

**如果不是這樣**：按了 Add variable 再按一次 **Add variable** 時，抽屜沒有清空、還留著上一個值：重新整理頁面，再展開 Variables 加下一個。

### 步驟 5-3：加 `DEPLOY_PASSWORD`（Masked、不保護）

**操作**：**Visibility** 選 **Masked**；**Protect variable** **取消勾選**；**Key** `DEPLOY_PASSWORD`、**Value** `Dep10y-Pa55w0rd` → **Add variable**。

![上半部：Masked、Protect variable 不勾](images/gitlab0/069-variable-drawer-masked-top.png)

![下半部：DEPLOY_PASSWORD](images/gitlab0/070-variable-drawer-masked.png)

**如果不是這樣**：Value 下面出現紅字、加不進去：Masked 的值有格式限制——至少 **8 個字元**、只能一行、不能有空白和某些特殊符號（Visibility 選項下的 **regular expressions requirements** 連結有完整規則）。

### 步驟 5-4：加 `PROD_DB_PASSWORD`（Masked＋Protected）

**操作**：**Visibility** 選 **Masked**；**Protect variable** **保持勾選**；**Key** `PROD_DB_PASSWORD`、**Value** `Pr0d-Db-Secret-2026` → **Add variable**。

![上半部：Masked、Protect variable 勾著](images/gitlab0/071-variable-drawer-protected-top.png)

![下半部：PROD_DB_PASSWORD](images/gitlab0/072-variable-drawer-protected.png)

![三個變數：DEPLOY_PASSWORD 標 Masked，PROD_DB_PASSWORD 標 Protected Masked](images/gitlab0/073-variables-list.png)

**你應該看到**：三個變數，Value 都是 `*****`。`DEPLOY_PASSWORD` 下面標 **Masked**，`PROD_DB_PASSWORD` 標 **Protected** **Masked**，`DEPLOY_USER` 沒有標籤。**Environments** 都是 **All (default)**（03b 會用到這一欄）。

**為什麼不是全部 Masked＋Protected 就好**：不是秘密的東西藏起來，除錯時反而看不到；而 Protected 一勾，feature 分支就拿不到，那個分支的 job 就測不了。**依值的敏感程度選等級**。

### 步驟 5-5：手動跑一條 main 的 pipeline，看變數注入

變數是 job **開始時**注入的，已經跑完的 pipeline 不會有。手動跑一條新的：

**操作**：**Build** → **Pipelines** → 右上 **New pipeline** → 出現 **Run new pipeline** 頁，**Run for branch name or tag** 選 `main` → 下面的 **New pipeline**。

![New pipeline：選 main](images/gitlab0/074-run-pipeline-main.png)

跑完後點 `secrets-demo` job：

![main 的 secrets-demo：密碼變成 [MASKED]，PROD_DB_PASSWORD 有注入](images/gitlab0/075-job-secrets-main.png)

**你應該看到**：

```
部署帳號：deployer
部署密碼：[MASKED]
PROD_DB_PASSWORD 已注入：[MASKED]
```

右側 **Source: Web**（手動從網頁觸發）。

**為什麼 main 拿得到 Protected 變數**：`main` 是 **protected branch**（建專案時 GitLab 自動保護預設分支，步驟 6-1 會看到）。

### 步驟 5-6：同樣手動跑 feature 分支

**操作**：再一次 **New pipeline**，這次選 `feature/break-test`。

![New pipeline：選 feature/break-test](images/gitlab0/076-run-pipeline-feature-break-test.png)

點這條 pipeline 的 `secrets-demo`：

![feature 分支的 secrets-demo：拿不到 PROD_DB_PASSWORD](images/gitlab0/077-job-secrets-feature.png)

**你應該看到**：`部署密碼：[MASKED]`（不保護的 Masked 變數拿得到），但最後一行是 **`這個分支拿不到 PROD_DB_PASSWORD（Protected）`**。

**為什麼這很重要**：
- **Masked 只是遮 log，不是加密。** job 裡的程式拿得到明文——有人在 job 裡寫 `echo $DEPLOY_PASSWORD | base64` 就看得到了。
- **Protected 才是真正的權限邊界。** 任何人都能開 feature 分支、在 MR 裡改 `.gitlab-ci.yml`；如果正式環境的密碼在那些 pipeline 裡拿得到，就等於所有開發者都拿得到。設成 Protected，只有能推 main（或推受保護 tag）的人觸發的 pipeline 才拿得到。

---

## Part 6：保護分支與 tag

### 步驟 6-1：看 Protected branches

**操作**：**Settings** → **Repository** → **Protected branches** 展開。

![Protected branches：main 已保護](images/gitlab0/078-protected-branches.png)

**你應該看到**：`main` 已經在列表裡（GitLab 自動保護預設分支）。**Allowed to merge**、**Allowed to push and merge** 是 Maintainers。上方藍色提示 Protected branches 之後會搬到 **Branch rules**，功能一樣。

### 步驟 6-2：保護 `v*` 的 tag

等一下要打 `v1.0.0` 這個 tag，它的 pipeline 要推正式版 image，也需要 Protected 變數。**tag 沒有保護的話，tag pipeline 拿不到 Protected 變數**，而且任何開發者都能隨手打一個 `v2.0.0`。

**操作**：同一頁 **Protected tags** 展開 → **Add tag**。

![Protected tags：No tags are protected](images/gitlab0/079-protected-tags-empty.png)

**Tag** 欄位輸入 `v*` → 下拉出現 **Create wildcard** → 點它。

![輸入 v*，選 Create wildcard](images/gitlab0/080-protected-tag-wildcard.png)

**Allowed to create** 選 **Maintainers** → **Protect**。

![Tag：v*；Allowed to create：Maintainers](images/gitlab0/081-protected-tag-form.png)

![v* 已保護](images/gitlab0/082-protected-tag-done.png)

**你應該看到**：列表多一行 `v*`，Allowed to create 是 Maintainers。

**為什麼用 `v*`**：一條規則就涵蓋 `v1.0.0`、`v1.0.1`、`v2.0.0`……所有版本 tag，不用每次發版都來加。

---

## Part 7：打版本 tag，找到 image

### 步驟 7-1：新增 tag `v1.0.0`

**操作**：左側 **Code** → **Tags** → 右上 **New tag**。

![Tags：還沒有 tag](images/gitlab0/083-tags-empty.png)

- **Tag name**：`v1.0.0`
- **Create from**：`main`
- **Message**：`DeployLog 第一個正式版`
- 按 **Create tag**

![New tag 表單](images/gitlab0/084-new-tag-form.png)

![v1.0.0 建好了](images/gitlab0/085-tag-created.png)

**為什麼要填 Message**：有 Message 的叫 **annotated tag**，會記錄誰、什麼時候、為什麼打這個版本。之後 Release 可以直接帶入這段訊息。

### 步驟 7-2：tag 的 pipeline

**操作**：**Build** → **Pipelines**。

![Pipelines：最上面是 v1.0.0 的 pipeline，標 tag](images/gitlab0/086-pipelines-list-final.png)

**你應該看到**：最上面一條，名稱下有 `v1.0.0` 和 **tag** 標籤，**Passed**。commit 編號 `b72c5e86` 跟 main 那條一樣——**同一份程式碼，多了一個版本名字**。

點進去：

![tag pipeline：四個 stage 全綠](images/gitlab0/087-pipeline-tag.png)

點 `secrets-demo`：

![tag pipeline 的 secrets-demo：PROD_DB_PASSWORD 已注入](images/gitlab0/088-job-secrets-tag.png)

**你應該看到**：`Checking out b72c5e86 as detached HEAD (ref is v1.0.0)`，最後 `PROD_DB_PASSWORD 已注入：[MASKED]`——因為 `v1.0.0` 符合受保護的 `v*`。

**如果不是這樣**：顯示「這個分支拿不到」：Part 6 的 Protected tags 沒做，或是先打 tag 才設保護。刪掉 tag（Code → Tags → 垃圾桶）、設好保護再重打。

回 pipeline，點 `docker-build`：

![docker-build log：推了 SHA 和 v1.0.0 兩個 tag](images/gitlab0/089-job-docker-tag.png)

**你應該看到**：先推 `b72c5e86`（`digest: sha256:64fe0e57…`），接著 `if [ -n "$CI_COMMIT_TAG" ]` 那段又推一次 `gitlab:5050/student/deploylog`，這次很多行 **Layer already exists**——**沒有重新 build，只是同一個 image 多掛一個名字**。

### 步驟 7-3：在 Container registry 看 image

**操作**：左側 **Deploy** → **Container registry**。

![Deploy 選單：Releases、Container registry](images/gitlab0/090-sidebar-deploy.png)

![Container registry：student/deploylog](images/gitlab0/091-registry-list.png)

點 image 名稱進去：

![兩個 tag：v1.0.0 和 b72c5e86，Digest 一樣](images/gitlab0/092-registry-tags.png)

**你應該看到**：兩個 tag——`v1.0.0` 和 `b72c5e86`，**Digest 都是 `64fe0e5`**。

**為什麼這很重要**：Digest 是 image 內容的指紋。兩個名字、同一個指紋＝**同一個 image**。這就是 **Immutable Artifact**：正式版不是「重新編一次」，而是把**測過的那一個**標上版本號。要追「v1.0.0 是哪次 commit 建的」，看 SHA 那個 tag 就知道。

---

## Part 8：下載產物、寫發版紀錄

### 步驟 8-1：Job artifacts：這一版編出來的檔案

**操作**：回 tag 的 pipeline，點 `publish` job。

![publish job：右側 Job artifacts 有 Keep／Download／Browse](images/gitlab0/093-job-publish.png)

**你應該看到**：log 有 `dotnet publish … -o ./publish`、`cp -R frontend/dist publish/wwwroot`、`Uploading artifacts... publish/: found 23 matching artifact files`。右側 **Job artifacts** 有三個按鈕：**Keep**、**Download**、**Browse**。

**操作**：**Browse**。

![Artifacts：publish 資料夾](images/gitlab0/094-artifacts-browse.png)

點 `publish`：

![publish/ 裡面：Api.dll、wwwroot…](images/gitlab0/095-artifacts-browse-publish.png)

**你應該看到**：`wwwroot`（前端）、`Api.dll`、`Api.deps.json` 等。右上 **Download artifacts archive** 可以整包下載成 zip，每個檔案右邊也能單獨下載。

**為什麼**：這就是部署要用的東西。M4 手動部署時，部署人員從某個人的電腦拿檔案；有了 CI，**每個版本的產物都存在 GitLab、跟 commit 綁在一起**。注意 `.gitlab-ci.yml` 裡 `publish` 的 `expire_in: 1 week`：產物一週後自動刪除（每個分支／tag 最新一次的會保留）。要永久保存的版本按 **Keep**，或靠下一步的 Release ＋ image。

### 步驟 8-2：建立 Release

**操作**：左側 **Deploy** → **Releases**。

![Releases：Getting started with releases](images/gitlab0/096-releases-empty.png)

**Create a new release**。**Tag name** 下拉 → 選 `v1.0.0`。

![Tag name 下拉：選 v1.0.0](images/gitlab0/097-release-tag-dropdown.png)

- **Release title**：`DeployLog v1.0.0`
- **Release date**：保留今天
- **Release notes**：

  ```
  第一個正式版本。
  - 後端 API + 前端打包成同一個 image：gitlab:5050/student/deploylog:v1.0.0
  - 單元測試 3 個全數通過
  ```

  （編輯器是所見即所得，打 `- ` 加空白會自動變成項目符號。）

![填好上半部](images/gitlab0/098-release-form-top.png)

往下捲到 **Release assets** → **Links**：

- **URL**：`http://gitlab:8929/student/deploylog/-/jobs/artifacts/v1.0.0/download?job=publish`
- **Link title**：`publish-artifacts.zip`
- **Type**：**Package**

按 **Create release**。

![Release assets：連結到 v1.0.0 的 publish 產物](images/gitlab0/099-release-form-assets.png)

**如果不是這樣**：**Create release** 是灰的：Links 的 URL 和 Link title 要**兩個都填**（不加連結就兩個都清空）。欄位下出現 **Link title is required** 但你明明填了：把那格清掉重新打一次，再按 Tab 離開欄位。

**為什麼這個網址**：`-/jobs/artifacts/<tag>/download?job=<job 名稱>` 是 GitLab 固定的格式，意思是「這個 tag 最新一次 `publish` job 的產物」。不寫死 job 編號，以後重跑也不會失效。

![Release 頁：DeployLog v1.0.0](images/gitlab0/100-release-created.png)

**你應該看到**：
- 標題 **DeployLog v1.0.0**，左邊是 commit `b72c5e86` 和 tag `v1.0.0`
- **Release notes**
- **Assets**：GitLab 自動附上四種格式的 **Source code**，加上你的 **Packages** → `publish-artifacts.zip`
- **Evidence collection**：GitLab 自動存一份這次發版當下的快照（JSON）

**為什麼要 Release**：tag 只是 git 裡的一個標記；Release 是給**人**看的發版紀錄——這版改了什麼、image 在哪、產物去哪下載，QA 和客服都找得到，不用來問開發者。

---

## Part 9：接下來

- **部署到 dev／qa／poc、Environment scope 變數、一鍵 Rollback**：[03b-gitlab-environments-release.md](03b-gitlab-environments-release.md)。那一段需要一台**專門部署用的 Runner**（掛在講師電腦的 Docker 上，把網站真的跑起來），課堂上由**講師示範**，你看截圖跟著理解。你的 `student-runner` 不帶 `deploy` tag，也不要替自己的 job 加 `tags: [deploy]`。
- `.gitlab-ci.yml` 每一行的意思：回 [03-m3-ci-pipeline.md](03-m3-ci-pipeline.md) Part A。

---

## 疑難排解

| 狀況 | 原因 | 處理 |
|------|------|------|
| http://gitlab:8929 打不開，http://localhost:8929 可以 | hosts 沒加 | 步驟 0-4 |
| 網頁顯示 502 | GitLab 還在開機，或記憶體不夠一直重開 | 等；`docker compose ps` 看是不是 healthy；調大記憶體（步驟 0-1） |
| root 登不進去 | 密碼太簡單被拒，或沒設 `GITLAB_ROOT_PASSWORD` | 步驟 0-5 的「如果密碼不對」 |
| `git push` 出現 `Access denied` | 用了登入密碼、或 token 少了 `write_repository` | 步驟 1-3 重建 token |
| 第一次 push 後就出現一條失敗的 pipeline | Auto DevOps | 步驟 1-4 最後；加了 `.gitlab-ci.yml` 就不會再有 |
| job 一直 Pending／stuck | 沒有 Runner 接 | Part 2；確認 Runner **Online** 且勾了 **Run untagged jobs** |
| job log：`Could not resolve host: gitlab` | job 容器沒接到 `ci-demo` 網路 | 註冊時少了 `--docker-network-mode ci-demo`：Runners 頁刪掉那台，重新建立、註冊 |
| `docker-build`：`server gave HTTP response to HTTPS client` | registry 沒 TLS | 步驟 3-2 修改 1 |
| `docker-build`：`Cannot connect to the Docker daemon` | Runner 沒開特權模式 | 註冊時要有 `--docker-privileged` |
| MR 紅燈還是能合併 | 沒開 Pipelines must succeed | 步驟 4-5 |
| tag pipeline 拿不到 Protected 變數 | tag 沒保護 | Part 6 步驟 6-2 |
| 上完課要關掉 | — | `docker compose stop`（資料保留，下次 `docker compose start`）；連資料一起刪：`docker compose down -v` |

---

截圖由 Playwright 照本文件步驟在瀏覽器實際操作產生（2026-11-02／03，GitLab CE 19.4.3、GitLab Runner 19.4.1）；終端機畫面是實際執行的輸出。Part 0 的終端機截圖取自講師電腦上已在執行的示範 GitLab（`ci-demo/`），所以開機時間不是「剛啟動」；步驟 2-2 的 Instance 分頁也因此看得到講師的兩台 instance runner。
