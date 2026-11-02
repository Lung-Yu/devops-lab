# 預檢啟動腳本（參考解答）：預檢全部通過，才啟動服務
# 用法（在 assets\ 目錄下）：powershell -ExecutionPolicy Bypass -File solutions\start.ps1 .env.poc
param([string]$EnvFile = ".env.poc")
$ErrorActionPreference = 'Stop'   # 任一指令失敗就停

# 把 .env 裡的 KEY=VALUE 讀成環境變數（# 開頭的是註解，跳過）
Get-Content $EnvFile | Where-Object { $_ -match '^[A-Za-z_]+=' } | ForEach-Object {
    $key, $value = $_ -split '=', 2
    Set-Item -Path "env:$key" -Value $value
}

Write-Host "[0/3] 檢查必填設定"
foreach ($name in 'EXTERNAL_API_URL', 'APP_PORT', 'DB_HOST', 'DB_PORT') {
    if (-not [Environment]::GetEnvironmentVariable($name)) {
        [Console]::Error.WriteLine("❌ 缺少環境變數 $name，請檢查 $EnvFile")
        exit 1
    }
}
Write-Host "✅ 必填設定齊全"

Write-Host "[1/3] 檢查外部服務：$env:EXTERNAL_API_URL"
try {
    Invoke-WebRequest -Uri "$env:EXTERNAL_API_URL/health" -TimeoutSec 3 -UseBasicParsing | Out-Null
} catch {
    [Console]::Error.WriteLine("❌ 無法連線到外部服務：$env:EXTERNAL_API_URL/health")
    [Console]::Error.WriteLine("   → 確認 mock-external-api 有在跑（docker compose ps），或檢查 $EnvFile 的 EXTERNAL_API_URL")
    exit 1
}
Write-Host "✅ 外部服務正常"

Write-Host "[2/3] 檢查 Port $env:APP_PORT 是否被佔用"
# 列出這台電腦正在 listen 的 TCP Port（Windows / Linux 都能用）
# Windows 也可以寫：Get-NetTCPConnection -LocalPort $env:APP_PORT -State Listen -ErrorAction SilentlyContinue
$listeners = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
if ($listeners | Where-Object { $_.Port -eq [int]$env:APP_PORT }) {
    [Console]::Error.WriteLine("❌ Port $env:APP_PORT 已被佔用")
    [Console]::Error.WriteLine("   → 關掉佔用的程式（docker ps 看是不是舊容器），或改 $EnvFile 的 APP_PORT")
    exit 1
}
Write-Host "✅ Port $env:APP_PORT 可用"

Write-Host "[3/3] 檢查資料庫：$($env:DB_HOST):$($env:DB_PORT)"
# 試著用 TCP 連線，3 秒內連得上就算通過（跟 pg_isready 同級，不驗帳密）
# Windows 也可以寫：Test-NetConnection $env:DB_HOST -Port $env:DB_PORT -InformationLevel Quiet
$ok = $false
try { $c = [Net.Sockets.TcpClient]::new(); $ok = $c.ConnectAsync($env:DB_HOST, [int]$env:DB_PORT).Wait(3000) } catch {} finally { if ($c) { $c.Dispose() } }
if (-not $ok) {
    [Console]::Error.WriteLine("❌ 無法連線到資料庫：$($env:DB_HOST):$($env:DB_PORT)")
    [Console]::Error.WriteLine("   → 確認 mock-db 有在跑（docker compose ps），或檢查 $EnvFile 的 DB_HOST / DB_PORT")
    exit 1
}
Write-Host "✅ 資料庫連線正常"

Write-Host "所有預檢通過，啟動服務..."
# 容器裡的 localhost 是容器自己，所以改用 host.docker.internal 連回這台電腦上的 mock-db
docker run --rm --name lab-api -p "$($env:APP_PORT):5000" --env-file $EnvFile `
    --add-host=host.docker.internal:host-gateway -e DB_HOST=host.docker.internal `
    keypasco-lab-api
exit $LASTEXITCODE
