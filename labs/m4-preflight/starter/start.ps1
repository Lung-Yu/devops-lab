# 預檢啟動腳本（學員起始檔）：把四個 TODO 補完，任一項失敗就 exit 1
# 用法（在 devops-lab\ 根目錄下）：powershell -ExecutionPolicy Bypass -File labs\m4-preflight\starter\start.ps1 .env.poc
param([string]$EnvFile = ".env.poc")
$ErrorActionPreference = 'Stop'   # 任一指令失敗就停

# 把 .env 裡的 KEY=VALUE 讀成環境變數（# 開頭的是註解，跳過）
Get-Content $EnvFile | Where-Object { $_ -match '^[A-Za-z_]+=' } | ForEach-Object {
    $key, $value = $_ -split '=', 2
    Set-Item -Path "env:$key" -Value $value
}

# TODO [0/3] 必填設定：EXTERNAL_API_URL、APP_PORT、DB_HOST、DB_PORT 少一個就停
#   提示：if (-not $env:DB_HOST) { [Console]::Error.WriteLine("❌ 缺少環境變數 DB_HOST，請檢查 $EnvFile"); exit 1 }

# TODO [1/3] 外部服務：try { Invoke-WebRequest -Uri "$env:EXTERNAL_API_URL/health" -TimeoutSec 3 -UseBasicParsing | Out-Null } catch { 印錯誤; exit 1 }

# TODO [2/3] Port：在下面這份「正在 listen 的 Port 清單」裡找到 APP_PORT = 被佔用 → 印錯誤、exit 1
#   $listeners = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
#   if ($listeners | Where-Object { $_.Port -eq [int]$env:APP_PORT }) { ... }

# TODO [3/3] 資料庫：用 TCP 連 DB_HOST:DB_PORT，3 秒內連不上 → 印錯誤、exit 1
#   $ok = $false
#   try { $c = [Net.Sockets.TcpClient]::new(); $ok = $c.ConnectAsync($env:DB_HOST, [int]$env:DB_PORT).Wait(3000) } catch {} finally { if ($c) { $c.Dispose() } }

# 錯誤訊息三要素：哪裡錯、為什麼、去哪修
# 錯誤訊息用 [Console]::Error.WriteLine("...") 印到 stderr，再 exit 1
# （不要用 Write-Error：搭配 Stop 會直接丟例外、印一大段紅字，後面的 exit 1 不會執行）

Write-Host "所有預檢通過，啟動服務..."
# 容器裡的 localhost 是容器自己，所以改用 host.docker.internal 連回這台電腦上的 mock-db
docker run --rm --name lab-api -p "$($env:APP_PORT):5000" --env-file $EnvFile `
    --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal `
    keypasco-lab-api
exit $LASTEXITCODE
