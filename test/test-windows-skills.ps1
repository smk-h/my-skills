# ========================================================
# windows-skills.ps1 端到端测试脚本
#
# 设计原则:
#   1. 自包含: 无论从什么状态开始, 测试结束都恢复成 -install 完整可用态
#   2. 不破坏仓库源: 校验 mirror/仓库 skill 文件 md5 全程不变 (除 update 验证场景)
#   3. trap EXIT 兜底: 中途失败也执行 cleanup, 不留垃圾
#   4. 断言式: 每个用例 PASS/FAIL, 最后汇总
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File .\test-windows-skills.ps1
#   powershell -ExecutionPolicy Bypass -File .\test-windows-skills.ps1 -Verbose  # 详细输出
# ========================================================

[CmdletBinding()]
param()

# ========================================================
# 全局配置
# ========================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

# 被测脚本路径 (与测试脚本同目录)
# 脚本在 test/ 子目录下，仓库根 = 上一级
$script:testDir = $PSScriptRoot
if (-not $script:testDir) { $script:testDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:repoRoot = Split-Path -Parent $script:testDir
$script:target = Join-Path $script:repoRoot "windows-skills.ps1"

# 关键路径
$script:repoSkills = Join-Path $script:repoRoot "skills"
$script:mirror     = Join-Path $env:USERPROFILE ".smskills"
$script:tools = @{
    claude   = Join-Path $env:USERPROFILE ".claude\skills"
    roo      = Join-Path $env:USERPROFILE ".roo\skills"
    zcode    = Join-Path $env:USERPROFILE ".zcode\skills"
    opencode = Join-Path $env:USERPROFILE ".config\opencode\skills"
    codebuddy = Join-Path $env:USERPROFILE ".codebuddy\skills"
}

# 仓库 skill 列表：动态扫描仓库 skills/ 目录下的子目录（不硬编码）
$script:skillNames = @()
if (Test-Path -LiteralPath $script:repoSkills) {
    $script:skillNames = Get-ChildItem -LiteralPath $script:repoSkills -Directory -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name | Sort-Object
}
$script:skillCount = $script:skillNames.Count
$script:toolKeys = @("claude", "roo", "zcode", "opencode", "codebuddy")

# 计数器
$script:pass = 0
$script:fail = 0
$script:failCases = @()
$script:Verbose = $PSBoundParameters.Verbose -or $false

# ========================================================
# 工具函数
# ========================================================

# 调用被测脚本 (静默, 只收集 stdout/stderr)
# 注意: 用 splatting @Args 给 powershell.exe -File 透参不稳定, 改用拼字符串调用
function Invoke-Target {
    param([string[]]$Arguments)
    $argStr = ($Arguments | ForEach-Object { $_ }) -join ' '
    $cmd = "& '$script:target' $argStr"
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1
    return ($out -join "`n")
}

# 取文件 md5 前 8 位
function Get-Md5Short {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return "MISSING" }
    $h = Get-FileHash -LiteralPath $Path -Algorithm MD5
    return $h.Hash.Substring(0, 8)
}

# 取目录下文件数 (递归)
function Get-FileCount {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    return @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue).Count
}

# 判断路径是否为 reparse point
function Test-IsLink {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $false }
    return ($item.Attributes.ToString() -match 'ReparsePoint')
}

# 记录仓库 skill md5 基线 (测试全程不变量)
function Get-RepoBaseline {
    $b = @{}
    foreach ($s in $script:skillNames) {
        $b[$s] = Get-Md5Short (Join-Path $script:repoSkills "$s\SKILL.md")
    }
    return $b
}

# ========================================================
# 断言
# ========================================================
function Assert-Case {
    param(
        [string]$Name,          # 用例名
        [scriptblock]$Check,    # 检查逻辑, 返回 $true/$false 或抛异常
        [string]$Detail = ""    # 失败详情
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
# Cleanup: 测试结束恢复成 -install 完整可用态
# ========================================================
function Cleanup {
    Write-Host ""
    Write-Host "恢复环境 -> -install ..." -ForegroundColor Yellow
    $null = Invoke-Target -Arguments @("-install")
    Write-Host "完成。" -ForegroundColor Yellow
}
trap { Cleanup; break }

# ========================================================
# 测试用例
# ========================================================

function Run-Tests {
    # 记录仓库基线 (不变量: 全程不变)
    $repoBaseline = Get-RepoBaseline

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "  windows-skills.ps1 端到端测试"
    Write-Host "=========================================="
    Write-Host "  target : $script:target"
    Write-Host "  repo   : $script:repoSkills"
    Write-Host "  mirror : $script:mirror"
    Write-Host "  tools  : $($script:toolKeys -join ', ')"
    Write-Host ""

    # --------------------------------------------------------
    # 0. 前置清理: 确保干净起点
    # --------------------------------------------------------
    Start-Group "前置清理"
    $null = Invoke-Target -Arguments @("-unlink", "all")
    if (Test-Path -LiteralPath $script:mirror) {
        Get-ChildItem -LiteralPath $script:mirror -Directory -Force -ErrorAction SilentlyContinue |
            ForEach-Object {
                if (Test-IsLink $_.FullName) { [System.IO.Directory]::Delete($_.FullName, $false) }
                else { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
            }
    }
    Write-Host "  (已清空 agent 链接与 mirror)" -ForegroundColor DarkGray

    # --------------------------------------------------------
    # 1. -h 帮助
    # --------------------------------------------------------
    Start-Group "1. -h (帮助)"
    $out = Invoke-Target -Arguments @("-h")
    Assert-Case "帮助菜单包含 Usage"     { $out.Contains('Usage:') } "实际输出前200字: $($out.Substring(0, [Math]::Min(200,$out.Length)))"
    Assert-Case "帮助菜单包含 -install"  { $out.Contains('-install') }
    Assert-Case "帮助菜单包含 -update"   { $out.Contains('-update') }
    Assert-Case "帮助菜单包含 -link"     { $out.Contains('-link') }
    Assert-Case "帮助菜单包含 -unlink"   { $out.Contains('-unlink') }
    Assert-Case "帮助菜单包含拓扑说明"   { $out.Contains('Topology') -or ($out.Contains('update') -and $out.Contains('link')) }

    # --------------------------------------------------------
    # 2. -install (update + link all)
    # --------------------------------------------------------
    Start-Group "2. -install (update + link all)"
    $null = Invoke-Target -Arguments @("-install")
    Assert-Case "mirror 已建立全部 skill ($($script:skillCount))" {
        $cnt = @(Get-ChildItem -LiteralPath $script:mirror -Directory -Force -ErrorAction SilentlyContinue).Count
        Write-Diag "mirror skill 数: $cnt (期望 $($script:skillCount))"
        $cnt -eq $script:skillCount
    } "mirror skill 数应为 $($script:skillCount)"
    Assert-Case "mirror 内容 = 仓库源 (逐个 md5)" {
        $ok = $true
        foreach ($s in $script:skillNames) {
            $m = Get-Md5Short (Join-Path $script:mirror "$s\SKILL.md")
            if ($m -ne $repoBaseline[$s]) { Write-Diag "${s}: mirror=$m repo=$($repoBaseline[$s])"; $ok = $false }
        }
        $ok
    }
    foreach ($tk in $script:toolKeys) {
        Assert-Case "${tk}: 全部 skill 为 Junction ($($script:skillCount))" {
            $n = 0; $linked = 0
            foreach ($s in $script:skillNames) {
                $p = Join-Path $script:tools[$tk] $s
                if (Test-Path -LiteralPath $p) {
                    $n++
                    if (Test-IsLink $p) { $linked++ }
                }
            }
            Write-Diag "${tk}: $linked/$n linked (期望 $($script:skillCount))"
            ($n -eq $script:skillCount) -and ($linked -eq $script:skillCount)
        }
        Assert-Case "${tk}: 链接内容 = 仓库源" {
            $ok = $true
            foreach ($s in $script:skillNames) {
                $a = Get-Md5Short (Join-Path $script:tools[$tk] "$s\SKILL.md")
                if ($a -ne $repoBaseline[$s]) { $ok = $false }
            }
            $ok
        }
    }

    # --------------------------------------------------------
    # 3. -status
    # --------------------------------------------------------
    Start-Group "3. -status (状态矩阵)"
    $out = Invoke-Target -Arguments @("-status")
    Assert-Case "status 含 mirror 路径" { $out.Contains($script:mirror) }
    Assert-Case "status 含所有 skill 名" {
        $ok = $true
        foreach ($s in $script:skillNames) { if (-not $out.Contains($s)) { $ok = $false } }
        $ok
    }
    Assert-Case "status 含所有工具名" {
        $ok = $true
        foreach ($tk in $script:toolKeys) { if (-not $out.Contains($tk)) { $ok = $false } }
        $ok
    }
    $expectedLinkPerRow = $script:toolKeys.Count
    Assert-Case "status 每个 skill 行有 $expectedLinkPerRow 个 LINK" {
        # 每个 skill 行应含 $expectedLinkPerRow 个 LINK
        $allOk = $true; $rowCnt = 0
        foreach ($ln in ($out -split "`n")) {
            # 判断是否为 skill 数据行（行内含某个 skill 名）
            $isSkill = $false
            foreach ($s in $script:skillNames) { if ($ln.Contains($s)) { $isSkill = $true; break } }
            if (-not $isSkill) { continue }
            $rowCnt++
            $c = ([regex]::Matches($ln, 'LINK')).Count
            if ($c -ne $expectedLinkPerRow) { Write-Diag "行 LINK 数=$c (期望 $expectedLinkPerRow) : $ln"; $allOk = $false }
        }
        $allOk -and ($rowCnt -ge $script:skillCount)
    } "每个 skill 行应出现 $expectedLinkPerRow 次 LINK"

    # --------------------------------------------------------
    # 4. -l (list)
    # --------------------------------------------------------
    Start-Group "4. -l (列表)"
    $out = Invoke-Target -Arguments @("-l")
    # 用实际显示名匹配 (大小写不敏感)
    $displayNames = @("Claude Code", "RooCode", "ZCode", "OpenCode", "CodeBuddy")
    Assert-Case "list 含所有工具显示名" {
        $lower = $out.ToLower()
        $ok = $true
        foreach ($n in $displayNames) { if (-not $lower.Contains($n.ToLower())) { $ok = $false } }
        $ok
    }
    Assert-Case "list 含所有 skill 名" {
        $ok = $true
        foreach ($s in $script:skillNames) { if (-not $out.Contains($s)) { $ok = $false } }
        $ok
    }
    Assert-Case "list 含 [link] 标记" { $out.Contains('[link]') }

    # --------------------------------------------------------
    # 5. -unlink + -link (拆建循环)
    # --------------------------------------------------------
    Start-Group "5. -unlink + -link (循环)"
    $mirrorFilesBefore = Get-FileCount $script:mirror
    $null = Invoke-Target -Arguments @("-unlink", "claude")
    Assert-Case "unlink claude 后 claude 目录空" {
        $cnt = @(Get-ChildItem -LiteralPath $script:tools['claude'] -Directory -Force -ErrorAction SilentlyContinue).Count
        Write-Diag "claude skill 数: $cnt"
        $cnt -eq 0
    }
    Assert-Case "unlink claude 不影响 mirror 源 (文件数不变)" {
        $now = Get-FileCount $script:mirror
        Write-Diag "mirror 文件数: before=$mirrorFilesBefore now=$now"
        $now -eq $mirrorFilesBefore
    } "mirror 文件数应保持 $mirrorFilesBefore"
    Assert-Case "unlink claude 不影响仓库源 (md5 不变)" {
        $ok = $true
        foreach ($s in $script:skillNames) {
            if ((Get-Md5Short (Join-Path $script:repoSkills "$s\SKILL.md")) -ne $repoBaseline[$s]) { $ok = $false }
        }
        $ok
    }

    $null = Invoke-Target -Arguments @("-link", "claude")
    Assert-Case "link claude 后全部 skill 重新链接 ($($script:skillCount))" {
        $linked = 0
        foreach ($s in $script:skillNames) {
            if (Test-IsLink (Join-Path $script:tools['claude'] $s)) { $linked++ }
        }
        Write-Diag "claude linked: $linked (期望 $($script:skillCount))"
        $linked -eq $script:skillCount
    }

    # --------------------------------------------------------
    # 6. -update (仓库改动 → 镜像同步)
    # --------------------------------------------------------
    Start-Group "6. -update (仓库改动同步)"
    $markerFile = Join-Path $script:repoSkills "markdowncli\SKILL.md"
    $origMd5 = Get-Md5Short $markerFile
    try {
        # 临时改动仓库文件
        Add-Content -LiteralPath $markerFile -Value "`n<!-- test-marker $(Get-Date -Format 'yyyyMMddHHmmss') -->" -Encoding UTF8
        $changedMd5 = Get-Md5Short $markerFile
        Write-Diag "仓库 markdowncli: $origMd5 -> $changedMd5"

        $null = Invoke-Target -Arguments @("-update")

        Assert-Case "update 后 mirror 同步仓库改动" {
            $m = Get-Md5Short (Join-Path $script:mirror "markdowncli\SKILL.md")
            Write-Diag "mirror markdowncli: $m (应=$changedMd5)"
            $m -eq $changedMd5
        }
        Assert-Case "update 后 agent 经链接即时读到新内容" {
            $a = Get-Md5Short (Join-Path $script:tools['claude'] "markdowncli\SKILL.md")
            Write-Diag "claude markdowncli: $a (应=$changedMd5)"
            $a -eq $changedMd5
        } "agent 应通过链接立即读到 update 后的内容"
    } finally {
        # 还原仓库 (git checkout)
        & git -C $script:repoRoot checkout -- $markerFile 2>$null
        $restored = Get-Md5Short $markerFile
        Write-Diag "仓库已还原: $restored (orig=$origMd5)"
        # 同步 mirror 回干净状态
        $null = Invoke-Target -Arguments @("-update")
    }
    Assert-Case "仓库文件已还原" {
        (Get-Md5Short $markerFile) -eq $origMd5
    }

    # --------------------------------------------------------
    # 7. -update (孤儿清理)
    # --------------------------------------------------------
    Start-Group "7. -update (孤儿清理)"
    $orphan = Join-Path $script:mirror "__orphan_test__"
    New-Item -Path $orphan -ItemType Directory -Force | Out-Null
    "fake" | Out-File -LiteralPath (Join-Path $orphan "SKILL.md") -Encoding UTF8
    $beforeCnt = @(Get-ChildItem -LiteralPath $script:mirror -Directory -Force).Count
    Write-Diag "造孤儿前 mirror skill 数: $beforeCnt"

    $out = Invoke-Target -Arguments @("-update")
    Assert-Case "update 清理了孤儿目录" {
        -not (Test-Path -LiteralPath $orphan)
    }
    Assert-Case "update 后 mirror skill 数 = $($script:skillCount)" {
        $cnt = @(Get-ChildItem -LiteralPath $script:mirror -Directory -Force).Count
        Write-Diag "mirror skill 数: $cnt (期望 $($script:skillCount))"
        $cnt -eq $script:skillCount
    }

    # --------------------------------------------------------
    # 8. 安全性终检
    # --------------------------------------------------------
    Start-Group "8. 仓库源完整性终检"
    Assert-Case "仓库全部 skill md5 全程未变 ($($script:skillCount))" {
        $ok = $true
        foreach ($s in $script:skillNames) {
            $now = Get-Md5Short (Join-Path $script:repoSkills "$s\SKILL.md")
            if ($now -ne $repoBaseline[$s]) { Write-Diag "${s}: $now != $($repoBaseline[$s])"; $ok = $false }
        }
        $ok
    }

    # --------------------------------------------------------
    # 汇总
    # --------------------------------------------------------
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "  测试汇总"
    Write-Host "=========================================="
    Write-Host ("  PASS: {0}" -f $script:pass) -ForegroundColor Green
    Write-Host ("  FAIL: {0}" -f $script:fail) -ForegroundColor $(if ($script:fail -gt 0) {'Red'} else {'DarkGray'})
    if ($script:failCases.Count -gt 0) {
        Write-Host ""
        Write-Host "  失败用例:" -ForegroundColor Red
        foreach ($c in $script:failCases) { Write-Host "    - $c" -ForegroundColor Red }
    }
    Write-Host ""

    return ($script:fail -eq 0)
}

# ========================================================
# 主入口
# ========================================================
try {
    $allOk = Run-Tests
} finally {
    Cleanup
}

if ($allOk) {
    Write-Host "✅ 全部测试通过" -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ 存在失败用例" -ForegroundColor Red
    exit 1
}
