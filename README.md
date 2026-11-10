# devops-lab

DevOps 實作課的 Lab 專案。範例網站 DeployLog：Vue3＋ASP.NET Core 10＋PostgreSQL，打包成一個 Docker image。

| 資料夾 | 內容 |
|--------|------|
| `assets/` | 上課所有 Lab 都在這裡做：範例網站（`lab-project/`）、docker compose（mock DB、mock 外部 API）、三個環境的 `.env.*`、M4 預檢腳本起始檔（`lab-m4-starter/`）與解答（`solutions/`）、環境檢查（`tools/selftest.*`）、GitLab CI 範例 yml |
| `assets/spring-demo/` | Java 組加碼：用 Spring Boot 對照 M2／M4／M5／M6（profile、必填設定、Actuator 健康檢查、結構化日誌、Flyway），共用同一個 mock-db 和 `.env.*`；Windows／Mac 操作步驟見該資料夾的 README |
| `ci-sample-repo/` | GitLab 練習要推上去的範例程式（不含 `.gitlab-ci.yml`，課堂上自己寫） |
| `docs/` | 手把手教程：`00-quickstart.md` 是環境啟動快速版，`README.md` 是全課程目錄 |

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

環境啟動看 [`docs/00-quickstart.md`](docs/00-quickstart.md)，各 Lab 的步驟看 [`docs/README.md`](docs/README.md)。Java 背景的同學可以另外看 [`assets/spring-demo/README.md`](assets/spring-demo/README.md)，同樣的概念用 Spring Boot 做一次，只需要 Docker。

## 關於帳號密碼

檔案裡出現的密碼（網站帳號 `Lab@2026`、資料庫 `labpass-demo` 等）都是**只在你自己電腦上跑的練習環境**用的假值，不連任何真實系統。拿這份專案改成自己的專案時，請換掉。
