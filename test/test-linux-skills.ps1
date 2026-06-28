# ========================================================
# test-linux-skills.ps1
# Windows 下的 linux-skills.sh 测试入口（PowerShell 直接调 docker）
#
# 架构:
#   PowerShell  ──[docker run]──▶  ubuntu:22.04 容器  ──[bash]──▶  test-linux-skills.sh
#   仓库挂载到容器 /workspace，无需 Git Bash 中转。
#
# 容器内执行的是 test-linux-skills.sh（纯测试逻辑），
# 该脚本同时也可在 Linux 主机上直接运行。
#
# 用法:
#   .\test-linux-skills.ps1        # 默认 ubuntu:22.04
#   .\test-linux-skills.ps1 -Image ubuntu:24.04
#   .\test-linux-skills.ps1 -Verbose
# ========================================================

[CmdletBinding()]
param(
    # 测试用的 docker 镜像（需含 bash）。默认 ubuntu:22.04
    [string]$Image = "ubuntu:22.04",
    # 容器内仓库挂载点
    [string]$Mount = "/workspace"
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
# 容器内：仓库挂载到 /workspace，测试脚本在 test/ 子目录
$testSh    = "test/test-linux-skills.sh"
$linuxSh   = "linux-skills.sh"

# ========================================================
# 前置检查
# ========================================================

# 1) docker 是否可用
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "❌ 未检测到 docker。请先安装并启动 Docker Desktop。" -ForegroundColor Red
    exit 2
}

try { $null = docker version 2>&1 } catch {
    Write-Host "❌ docker 未运行或无法连接。请启动 Docker Desktop。" -ForegroundColor Red
    exit 2
}

# 2) 测试脚本和被测脚本是否存在
foreach ($f in @($testSh, $linuxSh, "skills")) {
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
# 容器内命令：cd 到挂载点，确保换行符正常后跑测试脚本
# dos2unix 类问题：仓库文件若是 CRLF，bash 可能报错，用 sed 兜底不影响内容
$containerCmd = "bash `"$Mount/$testSh`" $verboseFlag"

# ========================================================
# 启动
# ========================================================
Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  linux-skills.sh 测试 (via docker)" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  host repo  : $repoPath" -ForegroundColor DarkGray
Write-Host "  container  : $Image" -ForegroundColor DarkGray
Write-Host "  mount      : $repoPath -> $Mount" -ForegroundColor DarkGray
Write-Host "  test script: $Mount/$testSh" -ForegroundColor DarkGray
Write-Host ""

# docker run：
#   --rm           退出即删容器
#   -v <repo>:<mount>  挂载仓库（可写：update 测试需改仓库验证同步）
#   -w <mount>     容器工作目录
#   -e HOME=/root  容器内 HOME（agent 工具目录落在 /root/.xxx）
# docker run --rm -it -v "${PWD}:/workspace" -w /workspace ubuntu:22.04 bash
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

exit $exitCode
