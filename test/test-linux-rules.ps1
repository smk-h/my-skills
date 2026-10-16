# ========================================================
# test-linux-rules.ps1
# Windows 下的 linux-rules.sh 测试入口（PowerShell 直接调 docker）
#
# 架构:
#   PowerShell  ──[docker run]──▶  ubuntu:22.04 容器  ──[bash]──▶  test-linux-rules.sh
#   仓库挂载到容器 /workspace，无需 Git Bash 中转。
#
# 容器内执行的是 test-linux-rules.sh（纯测试逻辑），其中 HOME 会被测试
# 自身指向临时沙箱，故容器内 /root 也不会被写入。
#
# 用法:
#   .\test-linux-rules.ps1        # 默认 ubuntu:22.04
#   .\test-linux-rules.ps1 -Image ubuntu:24.04
#   .\test-linux-rules.ps1 -Verbose
#   .\test-linux-rules.ps1 -StopDocker
# ========================================================

[CmdletBinding()]
param(
    # 测试用的 docker 镜像（需含 bash）。默认 ubuntu:22.04
    [string]$Image = "ubuntu:22.04",
    # 容器内仓库挂载点
    [string]$Mount = "/workspace",
    # 测试完毕后关闭 Docker Desktop（若本次是它自动拉起的则默认关闭）
    [switch]$StopDocker
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ========================================================
# 路径
# ========================================================
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

# 仓库根目录的 Windows 路径（docker -v 需要 Windows 风格，如 E:\AI\my-skills）
# 脚本在 test/ 子目录下，仓库根 = 上一级
$repoPath  = Split-Path -Parent $scriptDir
# 容器内路径
$testSh    = "test/test-linux-rules.sh"
$linuxSh   = "linux-rules.sh"

# ========================================================
# 前置检查
# ========================================================

# 1) docker 是否可用；未运行时尝试用 start-docker.ps1 自动拉起
$weStartedDocker = $false
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "❌ 未检测到 docker。请先安装并启动 Docker Desktop。" -ForegroundColor Red
    exit 2
}

# 注意: 用 --format 探服务器版本；docker 未运行时其报错会写 stderr，
# 在 $ErrorActionPreference='Stop' 下可能抛终止错误，故整体包 try/catch
$engineOk = $false
try {
    $null = docker version --format "{{.Server.Version}}" 2>&1
    if ($LASTEXITCODE -eq 0) { $engineOk = $true }
} catch { }
if (-not $engineOk) {
    Write-Host "docker 未运行，尝试自动启动 Docker Desktop..." -ForegroundColor Yellow
    # 子进程调用: start-docker.ps1 内部会执行 docker version（未运行时写 stderr），
    # 若同进程调用会继承本脚本的 $ErrorActionPreference='Stop' 而中断
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir "start-docker.ps1")
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Docker 引擎未能就绪。请手动启动 Docker Desktop。" -ForegroundColor Red
        exit 2
    }
    $weStartedDocker = $true
}

# 2) 测试脚本和被测脚本是否存在
foreach ($f in @($testSh, $linuxSh, "rules/AGENTS.md")) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoPath $f))) {
        Write-Host "❌ 缺少必要文件: $f (应在 $repoPath 下)" -ForegroundColor Red
        exit 2
    }
}

# 3) 镜像是否存在，不存在则 pull
$hasImage = docker image ls $Image --format '{{.Repository}}:{{.Tag}}' 2>$null
if (-not $hasImage) {
    Write-Host "镜像 $Image 不存在，正在 pull..." -ForegroundColor Yellow
    docker pull $Image
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ docker pull $Image 失败" -ForegroundColor Red
        exit 2
    }
}

# ========================================================
# 构造容器内命令
# ========================================================
$verboseFlag = ""
if ($PSBoundParameters.Verbose) { $verboseFlag = "-v" }
$containerCmd = "bash `"$Mount/$testSh`" $verboseFlag"

# ========================================================
# 启动
# ========================================================
Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  linux-rules.sh 测试 (via docker)" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  host repo  : $repoPath" -ForegroundColor DarkGray
Write-Host "  container  : $Image" -ForegroundColor DarkGray
Write-Host "  mount      : $repoPath -> $Mount" -ForegroundColor DarkGray
Write-Host "  test script: $Mount/$testSh" -ForegroundColor DarkGray
Write-Host ""

# docker run：
#   --rm            退出即删容器
#   -v <repo>:<mount>  挂载仓库
#   -w <mount>      容器工作目录
#   -e HOME=/root   容器内 HOME（测试自身会改用临时沙箱，/root 实际不被写入）
$exitCode = 0
& docker run --rm `
    -v "${repoPath}:${Mount}" `
    -w $Mount `
    -e HOME=/root `
    $Image `
    bash -c $containerCmd
$exitCode = $LASTEXITCODE

Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "✅ 测试通过（exit $exitCode）" -ForegroundColor Green
} else {
    Write-Host "❌ 测试失败（exit $exitCode）" -ForegroundColor Red
}

# 收尾: 指定 -StopDocker, 或本次由脚本自动拉起的 docker, 测试完关闭
# 收尾失败不应改变测试结论: 子进程调用 + 临时放宽 EAP（start-docker.ps1
# 的 docker version 探测在引擎已停时会写 stderr）
if ($StopDocker -or $weStartedDocker) {
    Write-Host "关闭 Docker Desktop..." -ForegroundColor Yellow
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir "start-docker.ps1") -Stop
    } catch {
        Write-Host "  (关闭 Docker 时出现异常, 已忽略: $($_.Exception.Message))" -ForegroundColor DarkYellow
    } finally {
        $ErrorActionPreference = $prevEap
    }
}

exit $exitCode
