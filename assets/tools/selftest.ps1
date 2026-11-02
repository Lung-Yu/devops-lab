# 課程環境自我測試（PowerShell 版，Windows PowerShell 5.1 / PowerShell 7 都能跑；bash 用 selftest.sh）
# 在 assets\ 目錄下執行：
#   powershell -ExecutionPolicy Bypass -File tools\selftest.ps1 env      # 只檢查環境——開課前請教室先跑
#   powershell -ExecutionPolicy Bypass -File tools\selftest.ps1 all      # 環境＋M2 三組切換＋M4 五種破壞＋/health＋M6 網站
#   powershell -ExecutionPolicy Bypass -File tools\selftest.ps1 m4 lab-m4-starter\start.ps1   # 抽查學員腳本
# 環境變數：LAB_PORT（預設 5000）
param([string]$Mode = "all", [string]$Script = "solutions\start.ps1")
$ErrorActionPreference = 'Continue'
$LabPort = if ($env:LAB_PORT) { [int]$env:LAB_PORT } else { 5000 }
$script:Pass = 0; $script:Fail = 0; $script:Warn = 0
$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("selftest-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $Tmp | Out-Null
$PsExe = (Get-Process -Id $PID).Path   # 用跟自己一樣的 PowerShell 執行受測腳本

function Ok($m)   { Write-Host "  [PASS] $m"; $script:Pass++ }
function Ng($m)   { Write-Host "  [FAIL] $m"; $script:Fail++ }
function Wn($m)   { Write-Host "  [WARN] $m"; $script:Warn++ }
function Section($m) { Write-Host ""; Write-Host "== $m ==" }
function Quiet { param([scriptblock]$b) & $b *> $null }

function Get-Status($url) {
    try { return [int](Invoke-WebRequest -Uri $url -TimeoutSec 3 -UseBasicParsing).StatusCode }
    catch { if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode } else { return 0 } }
}
function Wait-Status($url, $want, $sec) {
    for ($i = 0; $i -lt $sec; $i++) { if ((Get-Status $url) -eq $want) { return $true }; Start-Sleep 1 }
    return $false
}
function Test-PortListening($port) {
    $l = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    return [bool]($l | Where-Object { $_.Port -eq $port })
}
function Wait-Db {
    $id = (docker compose ps -q mock-db)
    for ($i = 0; $i -lt 30; $i++) {
        if ((docker inspect -f '{{.State.Health.Status}}' $id 2>$null) -eq 'healthy') { return $true }
        Start-Sleep 1
    }
    return $false
}

if (-not (Test-Path docker-compose.yml) -or -not (Test-Path lab-project)) {
    [Console]::Error.WriteLine("請在 assets\ 目錄下執行（要看得到 docker-compose.yml 和 lab-project\）"); exit 2
}

function Check-Env {
    Section "0. 環境"
    $v = docker version --format '{{.Server.Version}}' 2>$null
    if ($LASTEXITCODE -eq 0) { Ok "Docker 可用（server $v）" } else { Ng "Docker 沒有在跑，或沒有權限（docker version 失敗）" }
    docker compose version *> $null
    if ($LASTEXITCODE -eq 0) { Ok "docker compose 可用" } else { Ng "沒有 docker compose" }
    Ok "PowerShell $($PSVersionTable.PSVersion)"
    foreach ($url in 'https://registry-1.docker.io/v2/', 'https://mcr.microsoft.com/v2/', 'https://api.nuget.org/v3/index.json', 'https://registry.npmjs.org/', 'https://github.com') {
        $c = Get-Status $url
        if ($c -ne 0) { Ok "連得到 $url（HTTP $c）" } else { Wn "連不到 $url（已預載 image／改發 tar 檔的話可以忽略）" }
    }
    $published = (docker ps --format '{{.Ports}}') -join ' '
    foreach ($p in $LabPort, 5432, 8081) {
        if ((Test-PortListening $p) -and ($published -notmatch ":$p->")) { Ng "Port $p 被其他程式佔用" } else { Ok "Port $p 可用" }
    }
    $free = [math]::Floor((Get-PSDrive -Name (Get-Location).Drive.Name).Free / 1GB)
    if ($free -ge 5) { Ok "磁碟剩 $free GB" } else { Wn "磁碟只剩 $free GB（image 約需 3 GB）" }
    foreach ($img in 'keypasco-lab-api', 'postgres:16-alpine', 'nginx:alpine') {
        docker image inspect $img *> $null
        if ($LASTEXITCODE -eq 0) { Ok "image $img 已在本機" } else { Wn "image $img 還沒有（休息時要下載，或 docker load）" }
    }
}

function Start-Deps {
    Section "1. 啟動 mock 服務"
    docker compose up -d mock-db mock-external-api *> $null
    if ($LASTEXITCODE -ne 0) { Ng "docker compose up 失敗"; return $false }
    if (Wait-Db) { Ok "mock-db healthy" } else { Ng "mock-db 30 秒內沒有 healthy"; return $false }
    if ((Get-Status 'http://localhost:8081/health') -eq 200) { Ok "mock-external-api /health 200" } else { Ng "mock-external-api 沒有回應" }
    docker image inspect keypasco-lab-api *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  建置 keypasco-lab-api（第一次要下載 base image）..."
        docker build -q -t keypasco-lab-api lab-project *> $null
        if ($LASTEXITCODE -eq 0) { Ok "docker build 成功" } else { Ng "docker build 失敗"; return $false }
    } else { Ok "image keypasco-lab-api 已存在" }
    return $true
}

function Test-M2 {
    Section "2. Lab M2：三組 .env 不重新編譯切換"
    foreach ($t in @(@('dev', 'Development', 'labdb'), @('qa', 'QA', 'labdb_qa'), @('poc', 'POC', 'labdb_poc'))) {
        docker rm -f lab-api *> $null
        docker run -d --name lab-api -p "$($LabPort):5000" --env-file ".env.$($t[0])" keypasco-lab-api *> $null
        $want = '{"environment":"' + $t[1] + '","dbHost":"localhost","dbName":"' + $t[2] + '"}'
        $got = ''
        for ($i = 0; $i -lt 15 -and -not $got; $i++) {
            try { $got = (Invoke-WebRequest -Uri "http://localhost:$LabPort/whoami" -TimeoutSec 2 -UseBasicParsing).Content } catch { Start-Sleep 1 }
        }
        if ($got -eq $want) { Ok ".env.$($t[0]) → $got" } else { Ng ".env.$($t[0]) 預期 $want，實際 $got" }
    }
    docker rm -f lab-api *> $null
}

# 跑一次受測腳本：20 秒還沒結束 = 沒擋下、服務直接啟動了
function Expect-Block($desc, $envFile, $keyword) {
    $out = Join-Path $Tmp "out.txt"; $err = Join-Path $Tmp "err.txt"
    $p = Start-Process -FilePath $PsExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Script, $envFile) `
        -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -NoNewWindow
    if (-not $p.WaitForExit(20000)) {
        docker rm -f lab-api *> $null; $p.Kill()
        Ng "$desc → 沒有擋下（服務直接啟動了）"; return
    }
    $p.WaitForExit()
    $code = $p.ExitCode
    $text = (Get-Content $out, $err -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) -join "`n"
    if ($code -ne 0 -and $text -match [regex]::Escape($keyword)) { Ok "$desc → exit $code，訊息含「$keyword」" }
    elseif ($code -ne 0) { Wn "$desc → 有擋下（exit $code），但訊息沒有「$keyword」" }
    else { Ng "$desc → 沒有擋下（exit 0）" }
    docker rm -f lab-api *> $null
}

function Test-M4 {
    Section "3. Lab M4：預檢腳本 $Script"
    if (-not (Test-Path $Script)) { Ng "找不到 $Script"; return }
    $base = Join-Path $Tmp "env.base"
    (Get-Content .env.poc) -replace '^APP_PORT=.*', "APP_PORT=$LabPort" | Set-Content $base -Encoding ASCII

    $noHost = Join-Path $Tmp "env.nohost"
    Get-Content $base | Where-Object { $_ -notmatch '^DB_HOST=' } | Set-Content $noHost -Encoding ASCII
    Expect-Block "#0 缺 DB_HOST" $noHost "DB_HOST"

    docker compose stop mock-external-api *> $null
    Expect-Block "#1 外部服務停掉" $base "外部服務"
    docker compose start mock-external-api *> $null; Start-Sleep 1

    docker run -d --name squatter -p "$($LabPort):80" nginx:alpine *> $null; Start-Sleep 1
    Expect-Block "#2 Port $LabPort 被佔用" $base "佔用"
    docker rm -f squatter *> $null; Start-Sleep 1

    $typo = Join-Path $Tmp "env.typo"
    (Get-Content $base) -replace '^DB_HOST=.*', 'DB_HOST=localhsot' | Set-Content $typo -Encoding ASCII
    Expect-Block "#3 DB_HOST 打錯" $typo "資料庫"

    docker compose stop mock-db *> $null
    Expect-Block "#3 資料庫停掉" $base "資料庫"
    docker compose start mock-db *> $null; Wait-Db | Out-Null

    Section "4. 全部通過時啟動服務＋/health"
    $p = Start-Process -FilePath $PsExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Script, $base) `
        -RedirectStandardOutput (Join-Path $Tmp "run.txt") -RedirectStandardError (Join-Path $Tmp "run-err.txt") -PassThru -NoNewWindow
    if (Wait-Status "http://localhost:$LabPort/health" 200 30) { Ok "#4 四項預檢通過，服務啟動，/health 200" } else { Ng "#4 服務沒有起來" }
    docker compose stop mock-db *> $null
    if (Wait-Status "http://localhost:$LabPort/health" 503 15) { Ok "#5 DB 停掉後 /health 503" } else { Ng "#5 DB 停掉後 /health 不是 503" }
    docker compose start mock-db *> $null; Wait-Db | Out-Null
    if (Wait-Status "http://localhost:$LabPort/health" 200 20) { Ok "DB 恢復後 /health 回到 200" } else { Ng "DB 恢復後 /health 沒有回到 200" }
    docker rm -f lab-api *> $null
    if (-not $p.HasExited) { $p.Kill() }
}

# M6：migrate 前後 /health/ready、登入、三種角色的權限（後端擋，不是前端藏按鈕）
function Invoke-Status($url, $session, $body) {
    try {
        $r = Invoke-WebRequest -Uri $url -Method Post -ContentType 'application/json; charset=utf-8' -Body $body -WebSession $session -TimeoutSec 5 -UseBasicParsing
        return [int]$r.StatusCode
    } catch { if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode } else { return 0 } }
}
function Test-Web {
    Section "5. M6 範例網站：migrate、登入、權限"
    $h = @('--add-host=host.docker.internal:host-gateway', '-e', 'DB_HOST=host.docker.internal')
    $url = "http://localhost:$LabPort"
    docker compose exec -T mock-db psql -q -U labuser -d postgres -c "DROP DATABASE IF EXISTS labdb_poc WITH (FORCE)" -c "CREATE DATABASE labdb_poc" *> $null
    docker rm -f lab-api *> $null
    docker run -d --name lab-api -p "$($LabPort):5000" --env-file .env.poc @h keypasco-lab-api *> $null
    if (Wait-Status "$url/health/ready" 503 20) { Ok "還沒 migrate：/health/ready 503" } else { Ng "還沒 migrate 時 /health/ready 不是 503" }
    docker run --rm --env-file .env.poc @h -e DB_NAME=labdb_typo keypasco-lab-api migrate *> $null
    if ($LASTEXITCODE -ne 0) { Ok "DB_NAME 打錯：migrate exit 非 0，不會自己建新庫" } else { Ng "DB_NAME 打錯時 migrate 沒有失敗" }
    docker run --rm --env-file .env.poc @h keypasco-lab-api migrate *> $null
    if ($LASTEXITCODE -eq 0) { Ok "migrate 成功" } else { Ng "migrate 失敗" }
    if (Wait-Status "$url/health/ready" 200 10) { Ok "migrate 後 /health/ready 200" } else { Ng "migrate 後 /health/ready 不是 200" }
    if ((Get-Status "$url/") -eq 200) { Ok "首頁（Vue 前端）200" } else { Ng "首頁打不開" }
    if ((Get-Status "$url/api/deployments") -eq 401) { Ok "未登入讀資料 → 401" } else { Ng "未登入讀資料不是 401" }
    $body = '{"customer":"selftest","environment":"QA","version":"0.0.1","status":"Planned","deployedAt":"2026-11-03T05:30:00Z"}'
    foreach ($t in @(@('viewer', 403), @('engineer', 201))) {
        $s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        Invoke-Status "$url/api/auth/login" $s ('{"userName":"' + $t[0] + '","password":"Lab@2026"}') | Out-Null
        $got = Invoke-Status "$url/api/deployments" $s $body
        if ($got -eq $t[1]) { Ok "$($t[0]) 新增部署紀錄 → $got" } else { Ng "$($t[0]) 新增部署紀錄預期 $($t[1])，實際 $got" }
    }
    docker rm -f lab-api *> $null
}

try {
    switch ($Mode) {
        'env' { Check-Env }
        'm4'  { if (Start-Deps) { Test-M4 } }
        'all' { Check-Env; if (Start-Deps) { Test-M2; Test-M4; Test-Web } }
        default { [Console]::Error.WriteLine("用法：tools\selftest.ps1 [env|all|m4 <腳本>]"); exit 2 }
    }
} finally {
    docker rm -f lab-api squatter *> $null
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "結果：PASS $($script:Pass)／WARN $($script:Warn)／FAIL $($script:Fail)"
if ($script:Fail -eq 0) { exit 0 } else { exit 1 }
