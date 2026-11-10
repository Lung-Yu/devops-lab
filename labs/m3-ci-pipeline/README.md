# M3 Lab：CI Pipeline

**目標**：把一個專案推上 GitLab，自己寫 `.gitlab-ci.yml`，讓每次 push 都自動完成 build → test → package → docker。

完整步驟（含每個 GitLab 畫面的截圖）：
- 先讀懂 pipeline：[docs/03 M3 CI Pipeline](../../docs/03-m3-ci-pipeline.md)
- 動手做：[docs/03a GitLab 從 0 開始](../../docs/03a-gitlab-from-zero.md)

## 檔案

| 檔案／資料夾 | 是什麼 |
|-------------|--------|
| `sample-repo/` | 要推上 GitLab 的範例程式：DeployLog 的 .NET API（`src/Api`）、Vue3 前端（`frontend/`）、3 個單元測試（`tests/Api.Tests`）、`Dockerfile`。**刻意不含 `.gitlab-ci.yml`**，由你在 03a Part 3 自己加 |
| `gitlab-ci-dotnet-example.yml` | .NET 專案的 pipeline 範例。03a 要你複製進 `sample-repo` 的就是這份 |
| `gitlab-ci-java-war-example.yml` | Java（Maven）war 專案的 pipeline 範例，概念跟 .NET 版一樣，只是工具鏈不同。對照著讀，不用實際跑 |

## 怎麼用

照 03a 一步一步做：建專案 → 推程式（步驟 1-4，從 `devops-lab` 根目錄 `cd labs/m3-ci-pipeline/sample-repo` 再 `git init`）→ 註冊 Runner → 加 `.gitlab-ci.yml` → 看 pipeline。

沒有 GitLab 的話，03a Part 0 會教你在自己電腦架一台（Docker 要給 6 GB 以上記憶體）。講師課堂上示範用的那台在 [`instructor/ci-demo/`](../../instructor/ci-demo/)。
