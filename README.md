# devops-lab

DevOps 實作課的 Lab 專案。範例網站 DeployLog：Vue3＋ASP.NET Core 10＋PostgreSQL，打包成一個 Docker image。

| 資料夾 | 內容 |
|--------|------|
| `assets/` | 上課所有 Lab 都在這裡做：範例網站（`lab-project/`）、docker compose（mock DB、mock 外部 API）、三個環境的 `.env.*`、M4 預檢腳本起始檔（`lab-m4-starter/`）與解答（`solutions/`）、環境檢查（`tools/selftest.*`）、GitLab CI 範例 yml |
| `ci-sample-repo/` | GitLab 練習要推上去的範例程式（不含 `.gitlab-ci.yml`，課堂上自己寫） |

## 開始

```bash
git clone https://github.com/Lung-Yu/devops-lab.git
cd devops-lab/assets
```

講義說的「解壓 zip 後的 `assets/` 資料夾」就是這裡的 `assets/`。用 GitHub 的 Download ZIP 的話，解壓出來是 `devops-lab-main/assets/`。

需要 Docker Desktop（或 Docker Engine＋Compose）。進到 `assets/` 先跑環境檢查，全部 PASS 再開始：

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File tools\selftest.ps1 env
```

```bash
# macOS／Linux
bash tools/selftest.sh env
```

各 Lab 的步驟看課堂發的 Lab 手冊。

## 關於帳號密碼

檔案裡出現的密碼（網站帳號 `Lab@2026`、資料庫 `labpass-demo` 等）都是**只在你自己電腦上跑的練習環境**用的假值，不連任何真實系統。拿這份專案改成自己的專案時，請換掉。
