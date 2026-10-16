# ========================================================
# windows-rules.ps1 端到端测试脚本
#
# 设计原则:
#   1. 全程沙箱: 把 USERPROFILE 指向临时目录, 真实用户目录零触碰
#      (测试前后对真实目标做 md5 快照比对, 证明未被改动)
#   2. 不破坏仓库源: 校验 rules/AGENTS.md md5 全程不变
#   3. trap EXIT 兜底: 中途失败也清理沙箱
#   4. 断言式: 每个用例 PASS/FAIL, 最后汇总
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File .\test-windows-rules.ps1
#   powershell -ExecutionPolicy Bypass -File .\test-windows-rules.ps1 -Verbose
# ========================================================

[CmdletBinding()]
param()

# ========================================================
# 全局配置
# ========================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$script:testDir = $PSScriptRoot
if (-not $script:testDir) { $script:testDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:repoRoot = Split-Path -Parent $script:testDir
$script:target = Join-Path $script:repoRoot "windows-rules.ps1"

# 规则源（唯一真相）
$script:srcFile = Join-Path $script:repoRoot "rules\AGENTS.md"

# 真实用户目录（快照比对用；被测脚本的目标路径由 USERPROFILE 推导）
$script:realHome = $env:USERPROFILE

# 沙箱 HOME（被测脚本按 $env:USERPROFILE 计算所有目标路径）
$script:sandboxHome = Join-Path ([System.IO.Path]::GetTempPath()) ("rules-test-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))

# 被测脚本的工具表镜像（键 -> 目标路径 + 模式）
$script:targets = [ordered]@{
    claude    = @{ Path = Join-Path $script:sandboxHome ".claude\CLAUDE.md";                      Mode = "file" }
    zcode     = @{ Path = Join-Path $script:sandboxHome ".zcode\AGENTS.md";                       Mode = "file" }
    opencode  = @{ Path = Join-Path $script:sandboxHome ".config\opencode\AGENTS.md";             Mode = "file" }
    codebuddy = @{ Path = Join-Path $script:sandboxHome ".codebuddy\rules\agents-rules\RULE.mdc"; Mode = "rules" }
    dsh       = @{ Path = Join-Path $script:sandboxHome ".dsh\AGENTS.md";                         Mode = "file" }
}
$script:toolKeys = @($script:targets.Keys)
$script:fileKeys = @($script:toolKeys | Where-Object { $script:targets[$_].Mode -eq "file" })
$script:legacyCodebuddy = Join-Path $script:sandboxHome ".codebuddy\CODEBUDDY.md"

# 沙箱路径 -> 真实路径（用于零触碰不变量）
function Get-RealPath {
    param([string]$SandboxPath)
    return $SandboxPath.Replace($script:sandboxHome, $script:realHome)
}
$script:watchPaths = @{}
foreach ($k in $script:toolKeys) { $script:watchPaths[$k] = Get-RealPath $script:targets[$k].Path }
$script:watchPaths["legacy"] = Get-RealPath $script:legacyCodebuddy

# 计数器与上次调用结果
$script:pass = 0
$script:fail = 0
$script:failCases = @()
$script:lastOut = ""
$script:lastExit = 0
$script:Verbose = $PSBoundParameters.Verbose -or $false

# ========================================================
# 工具函数
# ========================================================

# 调用被测脚本（子进程 + 沙箱 USERPROFILE）
# 用 ProcessStartInfo 显式重定向三个流，原因:
#   1. stdin 可控: 交互确认(Read-Host)分支才能自动化 —— 管道喂 5.1 的 Read-Host 不可靠
#   2. stderr 单独收集为字符串: 避免 $ErrorActionPreference='Stop' 把原生命令 stderr
#      升级为终止错误（如 -link 非法工具时的 ValidateSet 报错）
# 结果写入 $script:lastOut / $script:lastExit
function Invoke-Target {
    param([string[]]$Arguments = @(), [string[]]$Answers = @())
    $prevHome = $env:USERPROFILE
    $env:USERPROFILE = $script:sandboxHome
    try {
        $argStr = ($Arguments | ForEach-Object { $_ }) -join ' '
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -Command "& ' + "'" + $script:target + "'" + ' ' + $argStr + '"'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.WorkingDirectory = $script:repoRoot

        $p = [System.Diagnostics.Process]::Start($psi)
        # 无输入时直接关掉 stdin: Read-Host 读到 EOF 返回空 -> 按「不覆盖」处理
        if ($Answers.Count -gt 0) {
            foreach ($a in $Answers) { $p.StandardInput.WriteLine($a) }
        }
        $p.StandardInput.Close()

        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        $script:lastExit = $p.ExitCode
        $script:lastOut = ($stdout + $stderr)
        return $script:lastOut
    } finally {
        $env:USERPROFILE = $prevHome
    }
}

# 取文件 md5 前 8 位（不存在返回 MISSING）
function Get-Md5Short {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return "MISSING" }
    return (Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash.Substring(0, 8)
}

# 目标是否与规则源字节一致
function Test-SameAsSource {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $script:srcFile -Algorithm SHA256).Hash)
}

# 规则源文本（LF 归一）
function Get-SrcText {
    $t = [System.IO.File]::ReadAllText($script:srcFile, [System.Text.Encoding]::UTF8)
    return ($t -replace "`r`n", "`n" -replace "`r", "`n")
}

# 无 BOM 且无 CR（纯 LF）
function Test-NoBomLf {
    param([string]$Path)
    $b = [System.IO.File]::ReadAllBytes($Path)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return $false }
    foreach ($x in $b) { if ($x -eq 13) { return $false } }
    return $true
}

# 写入任意内容（模拟「外部改动 / 不一致的目标」）
function Write-TextFile {
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

# 字节级复制规则源（模拟旧版脚本留下的 CODEBUDDY.md）
function Copy-SourceTo {
    param([string]$Path)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    [System.IO.File]::Copy($script:srcFile, $Path, $true)
}

# 统计全部目标中存在的文件数
function Get-PresentTargets {
    param([string[]]$Exclude = @())
    return @($script:toolKeys | Where-Object { $Exclude -notcontains $_ -and (Test-Path -LiteralPath $script:targets[$_].Path) })
}

# ========================================================
# 断言
# ========================================================
function Assert-Case {
    param(
        [string]$Name,
        [scriptblock]$Check,
        [string]$Detail = ""
    )
    try {
        $ok = & $Check
        if ($ok) {
            Write-Host "  [PASS] $Name" -ForegroundColor Green
            $script:pass++
        } else {
            Write-Host "  [FAIL] $Name" -ForegroundColor Red
            if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkRed }
            $script:fail++
            $script:failCases += $Name
        }
    } catch {
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        Write-Host "         异常: $($_.Exception.Message)" -ForegroundColor DarkRed
        $script:fail++
        $script:failCases += "$Name (异常)"
    }
}

function Start-Group {
    param([string]$Title)
    Write-Host ""
    Write-Host ("━━━ {0} ━━━" -f $Title) -ForegroundColor Cyan
}

function Write-Diag {
    param([string]$Msg)
    if ($script:Verbose) { Write-Host "    $Msg" -ForegroundColor DarkGray }
}

# ========================================================
# Cleanup（trap 兜底）
# ========================================================
function Remove-Sandbox {
    if (Test-Path -LiteralPath $script:sandboxHome) {
        Remove-Item -LiteralPath $script:sandboxHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

trap {
    Write-Host ""
    Write-Host "发生未捕获异常, 清理沙箱..." -ForegroundColor Yellow
    Remove-Sandbox
    Write-Host $_.Exception.Message -ForegroundColor DarkRed
    exit 1
}

# ========================================================
# 前置检查与环境准备
# ========================================================
if (-not (Test-Path -LiteralPath $script:target)) {
    Write-Host "❌ 被测脚本不存在: $($script:target)" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath $script:srcFile)) {
    Write-Host "❌ 规则源不存在: $($script:srcFile)" -ForegroundColor Red
    exit 2
}

$srcMd5 = Get-Md5Short $script:srcFile

# 真实用户目录快照（不变量：全程 md5 不变）
$realBefore = @{}
foreach ($k in $script:watchPaths.Keys) { $realBefore[$k] = Get-Md5Short $script:watchPaths[$k] }

New-Item -Path $script:sandboxHome -ItemType Directory -Force | Out-Null

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  windows-rules.ps1 测试" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  被测脚本  : $($script:target)" -ForegroundColor DarkGray
Write-Host "  规则源    : $($script:srcFile)  (md5 $srcMd5)" -ForegroundColor DarkGray
Write-Host "  沙箱 HOME : $($script:sandboxHome)" -ForegroundColor DarkGray
Write-Host "  工具      : $($script:toolKeys -join ', ')" -ForegroundColor DarkGray
Write-Host ""

# ========================================================
# A. 初始状态
# ========================================================
Start-Group "A. 初始状态（沙箱为空）"

$out = Invoke-Target @("-status")
Assert-Case "status 正常输出且退出码为 0" { ($out -match "source:") -and ($script:lastExit -eq 0) } $out
Assert-Case "status 报告 5 个目标全部 missing" {
    ([regex]::Matches($out, "\[missing\]")).Count -eq 5
} $out
Assert-Case "空沙箱下未创建任何目标" { (Get-PresentTargets).Count -eq 0 }

# ========================================================
# B. 安装
# ========================================================
Start-Group "B. 安装（-install -f）"

$out = Invoke-Target @("-install", "-f")
Assert-Case "install 成功返回" { $out -match "installed" } $out
Assert-Case "5 个目标文件全部创建" { (Get-PresentTargets).Count -eq 5 }
Assert-Case "4 个 file 目标与规则源字节一致" {
    @($script:fileKeys | Where-Object { -not (Test-SameAsSource $script:targets[$_].Path) }).Count -eq 0
}
Assert-Case "codebuddy RULE.mdc 无 BOM 且纯 LF" {
    Test-NoBomLf $script:targets["codebuddy"].Path
}
Assert-Case "codebuddy RULE.mdc front matter 为 always-apply" {
    $c = [System.IO.File]::ReadAllText($script:targets["codebuddy"].Path, [System.Text.Encoding]::UTF8)
    $c.StartsWith("---`n") -and $c -match "(?m)^alwaysApply: true$" -and $c -match "(?m)^enabled: true$" -and $c -match "(?m)^description: .+$"
}
Assert-Case "codebuddy RULE.mdc 正文与 AGENTS.md 全文一致" {
    $c = [System.IO.File]::ReadAllText($script:targets["codebuddy"].Path, [System.Text.Encoding]::UTF8)
    $idx = $c.IndexOf("---`n`n")
    ($idx -gt 0) -and ($c.Substring($idx + 5) -eq (Get-SrcText))
}
Assert-Case "install 提醒规则只在新会话生效" { $out -match "NEW chat sessions only" } $out

$out = Invoke-Target @("-status")
Assert-Case "status 报告 5 个目标全部 ok" {
    ([regex]::Matches($out, "\[ok\]")).Count -eq 5
} $out

$ruleMd5 = Get-Md5Short $script:targets["codebuddy"].Path
$claudeMd5 = Get-Md5Short $script:targets["claude"].Path
$out = Invoke-Target @("-install", "-f")
Assert-Case "重复 install 幂等（already up to date）" {
    ([regex]::Matches($out, "already up to date")).Count -eq 5
} $out
Assert-Case "重复 install 不改变已安装内容" {
    ((Get-Md5Short $script:targets["codebuddy"].Path) -eq $ruleMd5) -and ((Get-Md5Short $script:targets["claude"].Path) -eq $claudeMd5)
}

# ========================================================
# C. 覆盖策略（不一致才询问）
# ========================================================
Start-Group "C. 覆盖策略（询问 / 强制 / 跳过）"

Write-TextFile -Path $script:targets["claude"].Path -Text "foreign content`n"
$out = Invoke-Target @("-link", "claude") -Answers @("n")
Assert-Case "不一致 + 答 n -> 跳过" { $out -match "skipped" } $out
Assert-Case "答 n 后目标内容未变" {
    [System.IO.File]::ReadAllText($script:targets["claude"].Path).Trim() -eq "foreign content"
}

$out = Invoke-Target @("-link", "claude") -Answers @("y")
Assert-Case "不一致 + 答 y -> 覆盖并匹配仓库源" {
    ($out -match "updated") -and (Test-SameAsSource $script:targets["claude"].Path)
} $out

Write-TextFile -Path $script:targets["claude"].Path -Text "foreign content`n"
$out = Invoke-Target @("-link", "claude", "-f")
Assert-Case "不一致 + -f -> 不询问直接覆盖" {
    ($out -match "updated") -and (Test-SameAsSource $script:targets["claude"].Path)
} $out

Write-TextFile -Path $script:targets["codebuddy"].Path -Text "foreign rule`n"
$out = Invoke-Target @("-link", "codebuddy") -Answers @("n")
Assert-Case "codebuddy 规则不一致 + 答 n -> 跳过" { $out -match "skipped" } $out
Assert-Case "codebuddy 规则被跳过时内容未变" {
    [System.IO.File]::ReadAllText($script:targets["codebuddy"].Path).Trim() -eq "foreign rule"
}

$null = Invoke-Target @("-install", "-f")
$out = Invoke-Target @("-status")
Assert-Case "install -f 恢复全部 ok" {
    ([regex]::Matches($out, "\[ok\]")).Count -eq 5
} $out

# ========================================================
# D. 旧版 CODEBUDDY.md 迁移清理
# ========================================================
Start-Group "D. 旧版 CODEBUDDY.md 清理"

Copy-SourceTo -Path $script:legacyCodebuddy
$out = Invoke-Target @("-link", "codebuddy", "-f")
Assert-Case "与源一致的旧文件被清理并提示" {
    (-not (Test-Path -LiteralPath $script:legacyCodebuddy)) -and ($out -match "removed legacy file")
} $out

Write-TextFile -Path $script:legacyCodebuddy -Text "user modified legacy`n"
$out = Invoke-Target @("-link", "codebuddy", "-f")
Assert-Case "改动过的旧文件被保留" {
    (Test-Path -LiteralPath $script:legacyCodebuddy) -and ($out -match "legacy file kept")
} $out

$out = Invoke-Target @("-status")
Assert-Case "status 提示旧文件不会被加载" { $out -match "NOT loaded by CodeBuddy" } $out

# ========================================================
# E. 卸载（仅删与源一致的文件）
# ========================================================
Start-Group "E. 卸载"

Write-TextFile -Path $script:targets["dsh"].Path -Text "foreign content`n"
$out = Invoke-Target @("-unlink", "dsh")
Assert-Case "改动过的目标不被删除" {
    (Test-Path -LiteralPath $script:targets["dsh"].Path) -and ($out -match "skipped")
} $out

$out = Invoke-Target @("-unlink", "all")
Assert-Case "unlink all 删除 4 个一致目标，保留改动过的 dsh" {
    ((Get-PresentTargets).Count -eq 1) -and (Test-Path -LiteralPath $script:targets["dsh"].Path)
} $out
Assert-Case "unlink codebuddy 连同规则目录一并移除" {
    -not (Test-Path -LiteralPath (Split-Path -Parent $script:targets["codebuddy"].Path))
}

$out = Invoke-Target @("-status")
Assert-Case "status: 4 个 missing + dsh differs" {
    (([regex]::Matches($out, "\[missing\]")).Count -eq 4) -and ($out -match "\[differs\]")
} $out

# ========================================================
# F. 边界与不变量
# ========================================================
Start-Group "F. 边界与不变量"

# -link / -unlink 带 [ValidateSet]，非法工具由参数绑定直接拦截（非零退出）
$out = Invoke-Target @("-link", "nosuchtool")
Assert-Case "未知工具被拒绝且退出码非 0" {
    ($script:lastExit -ne 0) -and ($out -match "does not belong to the set|Cannot validate argument")
} $out
Assert-Case "未知工具未新增任何目标" { (Get-PresentTargets).Count -eq 1 }

$out = Invoke-Target @("-h")
Assert-Case "-h 打印帮助" { $out -match "Rules Installer for AI Extensions" } $out

$out = Invoke-Target @()
Assert-Case "无参数兜底为帮助" { $out -match "Usage:" } $out

Assert-Case "仓库规则源全程未被改动" { (Get-Md5Short $script:srcFile) -eq $srcMd5 }
Assert-Case "真实用户目录零触碰（md5 快照一致）" {
    $script:realUntouched = $true
    foreach ($k in $script:watchPaths.Keys) {
        if ((Get-Md5Short $script:watchPaths[$k]) -ne $realBefore[$k]) { $script:realUntouched = $false }
    }
    $script:realUntouched
} ("真实路径: " + (($script:watchPaths.Keys | ForEach-Object { "$_=$(Get-Md5Short $script:watchPaths[$_])" }) -join " "))

# ========================================================
# 汇总
# ========================================================
Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ("  结果: {0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail -eq 0) { "Green" } else { "Red" })
if ($script:fail -gt 0) {
    Write-Host "  失败用例:" -ForegroundColor Red
    foreach ($c in $script:failCases) { Write-Host "    - $c" -ForegroundColor DarkRed }
}
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

Remove-Sandbox

exit $(if ($script:fail -eq 0) { 0 } else { 1 })
