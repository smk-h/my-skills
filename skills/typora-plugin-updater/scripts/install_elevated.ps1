# Typora Plugin 提权安装脚本（自包含，可重复运行）
#
# 用途：在新版 plugin 目录（staging）就绪后，由 UAC 提权进程调用，
#       将其同步到 Typora 的 resources/plugin 目录，注入 window.html，
#       并保护/恢复用户自定义配置。
#
# 参数：
#   -StagingDir  新版 plugin 目录的绝对 Windows 路径（必填）
#   -LogPath     日志文件绝对 Windows 路径（必填，调用方据此读结果）
#
# 设计要点（均来自实战踩坑）：
#   1. 不调用官方 install_windows.ps1——它在管理员上下文里会再次自我提权，
#      触发异常导致窗口闪退（退出码 -196608）。改为本脚本自包含完成全部步骤。
#   2. robocopy /MIR 会用新版默认值覆盖用户配置，故 robocopy 前先备份
#      settings.user.toml / custom_plugin.user.toml / user_space / user_styles，
#      robocopy 后无条件恢复。
#   3. 日志路径必须由调用方传入绝对路径，不能依赖 $env:TEMP（提权后可能变化）。

param(
    [Parameter(Mandatory=$true)][string]$StagingDir,
    [Parameter(Mandatory=$true)][string]$LogPath
)

$ErrorActionPreference = "Continue"

function Log($m) {
    $m | Out-File -FilePath $LogPath -Encoding UTF8 -Append
    Write-Output $m
}

# 清空旧日志，写入起始标记
"=== Typora Plugin 提权安装开始: $(Get-Date) ===" | Out-File -FilePath $LogPath -Encoding UTF8

# 脚本级变量：用户配置临时备份目录。成功时删除、失败时保留，故在 try/catch 外声明
$script:tmpUser = $null

try {
    # --- 探测 Typora resources 目录（含 window.html 的目录）---
    $candidates = @(
        "C:\Program Files\Typora\resources",
        "C:\Program Files (x86)\Typora\resources",
        "$env:LOCALAPPDATA\Programs\Typora\resources"
    )
    $res = $null
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "window.html")) { $res = $c; break }
    }
    if (-not $res) { throw "未找到 Typora resources 目录（含 window.html）" }
    $plugin  = Join-Path $res "plugin"
    $winHtml = Join-Path $res "window.html"
    Log "Typora resources: $res"

    if (-not (Test-Path $StagingDir)) { throw "staging 目录不存在: $StagingDir" }

    # --- [1/7] 关闭 Typora，避免文件占用 ---
    Log "[1/7] 关闭 Typora 进程"
    $tp = Get-Process -Name "Typora" -ErrorAction SilentlyContinue
    if ($tp) {
        $tp | ForEach-Object { Log "  -> 关闭 PID $($_.Id)" }
        $tp | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } else { Log "  -> Typora 未运行" }

    # --- [2/7] 备份现有用户自定义数据（robocopy 前保护）---
    # 这些是用户数据，新版本里没有或为默认值，必须跨过 robocopy 保留
    $protected = @{
        "global\settings\settings.user.toml"      = $null
        "global\settings\custom_plugin.user.toml" = $null
    }
    Log "[2/7] 备份用户自定义配置与数据"
    foreach ($rel in $protected.Keys) {
        $src = Join-Path $plugin $rel
        if (Test-Path $src) {
            $protected[$rel] = Get-Content $src -Raw -Encoding UTF8
            Log "  -> 已读取 $rel ($(($protected[$rel]).Length) 字节)"
        }
    }
    # user_space / user_styles 整目录用 robocopy 备份到临时区
    $script:tmpUser = Join-Path $env:TEMP "typora_plugin_user_backup_$(Get-Date -Format yyyyMMddHHmmss)"
    foreach ($d in @("user_space","user_styles")) {
        $src = Join-Path $plugin "global\$d"
        if (Test-Path $src) {
            $dst = Join-Path $tmpUser $d
            robocopy $src $dst /E /NFL /NDL /NJH /NJS /NP | Out-Null
            Log "  -> 已备份目录 global\$d"
        }
    }

    # --- [3/7] robocopy 镜像同步 staging -> 目标 plugin ---
    Log "[3/7] robocopy 同步 $StagingDir -> $plugin"
    if (-not (Test-Path $plugin)) { New-Item -ItemType Directory -Path $plugin | Out-Null }
    robocopy $StagingDir $plugin /MIR /NFL /NDL /NJH /NJS /NP /XD .git | Out-Null
    Log "      robocopy exit=$LASTEXITCODE"
    if ($LASTEXITCODE -ge 8) { throw "robocopy 失败，退出码 $LASTEXITCODE" }

    # --- [4/7] 恢复用户自定义配置与数据（无论 robocopy 是否改动，无条件恢复）---
    Log "[4/7] 恢复用户自定义配置与数据"
    foreach ($rel in $protected.Keys) {
        if ($null -ne $protected[$rel]) {
            $dst = Join-Path $plugin $rel
            Set-Content -Path $dst -Value $protected[$rel] -Encoding UTF8 -NoNewline
            Log "  -> 已恢复 $rel ($(($protected[$rel]).Length) 字节)"
        }
    }
    foreach ($d in @("user_space","user_styles")) {
        $src = Join-Path $tmpUser $d
        if (Test-Path $src) {
            $dst = Join-Path $plugin "global\$d"
            robocopy $src $dst /E /NFL /NDL /NJH /NJS /NP | Out-Null
            Log "  -> 已恢复目录 global\$d"
        }
    }

    # --- [5/7] 注入 window.html（定位 frame.js 锚点，其后追加 plugin/index.js）---
    Log "[5/7] 注入 window.html"
    $pluginScript = '<script src="./plugin/index.js" defer="defer"></script>'
    $content = Get-Content $winHtml -Raw -Encoding UTF8
    if ($content -match [Regex]::Escape($pluginScript)) {
        Log "      已存在注入，跳过"
    } else {
        $frameNew = '<script src="./appsrc/window/frame.js" defer="defer"></script>'
        $frameOld = '<script src="./app/window/frame.js" defer="defer"></script>'
        $injected = $false
        if ($content -match [Regex]::Escape($frameNew)) {
            $content = $content -replace [Regex]::Escape($frameNew), ($frameNew + $pluginScript)
            Log "      注入于 appsrc/window/frame.js 之后（新版 Typora）"
            $injected = $true
        } elseif ($content -match [Regex]::Escape($frameOld)) {
            $content = $content -replace [Regex]::Escape($frameOld), ($frameOld + $pluginScript)
            Log "      注入于 app/window/frame.js 之后（免费版 Typora）"
            $injected = $true
        }
        if (-not $injected) { throw "window.html 中未找到 frame.js 锚点，无法注入" }
        Set-Content $winHtml -Value $content -Encoding UTF8 -NoNewline
    }

    # --- [6/7] 赋予 Users 完全控制权限（插件运行期需写配置/缓存）---
    Log "[6/7] 设置目录与配置文件权限"
    $users = New-Object System.Security.Principal.SecurityIdentifier(
        [System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)
    $acl = Get-Acl $plugin
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $users, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $plugin $acl
    foreach ($rel in @("global\settings\settings.user.toml","global\settings\custom_plugin.user.toml")) {
        $fp = Join-Path $plugin $rel
        if (Test-Path $fp) {
            $fa = Get-Acl $fp
            $fr = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $users, "FullControl", "Allow")
            $fa.ResetAccessRule($fr)
            Set-Acl $fp $fa
        }
    }
    Log "      权限已设置"

    # --- [7/7] 校验（作为成功/失败判定，非仅记录）---
    Log "[7/7] 校验安装结果"
    $checks = @()
    $chk = Get-Content $winHtml -Raw -Encoding UTF8
    $injectOk = $chk -match [Regex]::Escape($pluginScript)
    $checks += [PSCustomObject]@{ Item = "window.html 注入"; Pass = $injectOk }
    if ($injectOk) { Log "      [OK] window.html 注入成功" } else { Log "      [FAIL] window.html 未检测到注入" }

    $cfg = Join-Path $plugin "global\settings\settings.user.toml"
    $cfgOk = $true
    if (Test-Path $cfg) {
        $cfgLen = (Get-Item $cfg).Length
        Log "      settings.user.toml = $cfgLen 字节"
        # 若第 2 步备份过该文件，校验恢复后字节数应与备份一致
        $rel = "global\settings\settings.user.toml"
        if ($null -ne $protected[$rel]) {
            $cfgOk = ($cfgLen -eq ($protected[$rel]).Length)
            if ($cfgOk) { Log "      [OK] 用户配置字节数与备份一致" }
            else { Log "      [FAIL] 用户配置字节数与备份不符（$cfgLen != $(($protected[$rel]).Length)）" }
        }
    }
    $checks += [PSCustomObject]@{ Item = "用户配置完整"; Pass = $cfgOk }

    $cnt = (Get-ChildItem $plugin -ErrorAction SilentlyContinue | Measure-Object).Count
    Log "      plugin 顶层条目数 = $cnt"

    # 汇总判定：所有检查通过才算成功
    $allPass = ($checks | Where-Object { -not $_.Pass }).Count -eq 0
    if (-not $allPass) { throw "校验未通过：$(($checks | Where-Object { -not $_.Pass } | ForEach-Object { $_.Item }) -join ', ')" }

    # 校验全过：删除本脚本创建的临时用户配置备份目录
    if ($script:tmpUser -and (Test-Path $script:tmpUser)) {
        Remove-Item $script:tmpUser -Recurse -Force -ErrorAction SilentlyContinue
        Log "      已清理临时备份 $script:tmpUser"
    }

    Log "=== 成功完成: $(Get-Date) ==="
    "SUCCESS" | Out-File -FilePath $LogPath -Encoding UTF8 -Append
}
catch {
    Log "[ERROR] $($_.Exception.Message)"
    # 失败时保留临时备份以便回滚，仅记录其位置
    if ($script:tmpUser -and (Test-Path $script:tmpUser)) {
        Log "临时备份保留于: $script:tmpUser"
    }
    Log "=== 失败: $(Get-Date) ==="
    "FAILED" | Out-File -FilePath $LogPath -Encoding UTF8 -Append
}
