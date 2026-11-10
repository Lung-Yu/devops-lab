# tools：自我檢查與講師工具

所有指令都在 `devops-lab` 根目錄下執行（不是在 tools 裡）。

## selftest：環境與 Lab 自我檢查

| 模式 | 什麼時候用 | 檢查什麼 |
|------|-----------|---------|
| `env` | **課前，每個人都要跑** | Docker、compose、對外連線（Docker Hub、mcr、nuget、npm、GitHub）、Port 5000／5432／8081、磁碟空間、image 在不在 |
| `all` | 講師課前驗收 | `env`＋M2 三組 `.env` 切換＋M4 五種破壞＋`/health`＋M6 網站（migrate、登入、權限） |
| `m4 <腳本>` | M4 檢核點：抽查某個人寫的預檢腳本 | 對指定的腳本跑五種破壞，看是不是都被擋下來 |

```powershell
# Windows（PowerShell）
powershell -ExecutionPolicy Bypass -File tools\selftest.ps1 env
powershell -ExecutionPolicy Bypass -File tools\selftest.ps1 m4 labs\m4-preflight\starter\start.ps1
```

```bash
# macOS／Linux
bash tools/selftest.sh env
bash tools/selftest.sh m4 labs/m4-preflight/starter/start.sh
```

最後一行是 `結果：PASS n／WARN n／FAIL 0` 就代表通過。WARN 通常是 image 還沒下載，照 [docs/00-quickstart.md](../docs/00-quickstart.md) 第 5 步補上即可。

Mac 的 port 5000 被 AirPlay 佔用時，前面加 `LAB_PORT=5050`：`LAB_PORT=5050 bash tools/selftest.sh all`。

`all` 和 `m4` 會自己起、自己刪一個叫 `lab-api` 的容器。你原本開著的 `lab-api` 會被換掉，跑完要重新啟動。

## make-offline-bundle.sh（講師用）

教室網路慢、或連不到 Docker Hub／mcr／nuget.org 時，課前先在講師電腦打包好 image，用隨身碟發給學員：

```bash
bash tools/make-offline-bundle.sh            # 產出 keypasco-lab-images-amd64.tar（約 600 MB）
```

學員端在 `devops-lab` 下執行 `docker load -i keypasco-lab-images-amd64.tar` 即可。

在 Apple Silicon 上會用模擬方式建置 amd64，比較慢。做完之後，本機同名的 image 會變成 amd64 版，要重跑 `docker build -t keypasco-lab-api apps/dotnet-deploylog` 換回原生版。
