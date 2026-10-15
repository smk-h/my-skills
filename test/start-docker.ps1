# ========================================================
# start-docker.ps1 - 确保 Docker 引擎可用 (Windows)
#
# 用途:
#   测试脚本（如 test-linux-skills.ps1）的前置依赖。
#   Docker 未运行时自动拉起 Docker Desktop（应用内部会自行
#   通过 UAC 提权启动 com.docker.service），并轮询等待引擎就绪。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File .\start-docker.ps1              # 启动并等待就绪
#   powershell -ExecutionPolicy Bypass -File .\start-docker.ps1 -TimeoutSeconds 120
#   powershell -ExecutionPolicy Bypass -File .\start-docker.ps1 -Stop        # 关闭 Docker Desktop
#
# 退出码:
#   0 = 引擎就绪（原本就在运行，或本次启动成功）
#   2 = 启动失败 / 等待超时
# ========================================================

[CmdletBinding()]
param(
    # 等待引擎就绪的最长秒数
    [int]$TimeoutSeconds = 90,

    # 关闭 Docker Desktop（测试完毕后释放资源用）
    [switch]$Stop
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --------------------------------------------------------
# 引擎是否就绪
# --------------------------------------------------------
function Test-DockerEngine {
    docker version *> $null
    return ($LASTEXITCODE -eq 0)
}

# --------------------------------------------------------
# 尝试拉起 Docker Desktop 应用
# 返回: $true=已启动(或已在运行) $false=找不到可执行文件
# --------------------------------------------------------
function Start-DockerDesktop {
    $candidates = @(
        (Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"),
        (Join-Path $env:ProgramW6432 "Docker\Docker\Docker Desktop.exe")
    )
    foreach ($exe in $candidates) {
        if ($exe -and (Test-Path -LiteralPath $exe)) {
            Write-Host "  启动 Docker Desktop: $exe" -ForegroundColor Cyan
            Start-Process -FilePath $exe
            return $true
        }
    }
    return $false
}

# --------------------------------------------------------
# 关闭 Docker Desktop, 并轮询确认引擎已停止
# 返回: $true=已停止 $false=超时仍在运行
# --------------------------------------------------------
function Stop-DockerDesktop {
    param([int]$TimeoutSeconds = 30)

    if (-not (Test-DockerEngine)) {
        Write-Host "  Docker 引擎本就未在运行" -ForegroundColor Green
        return $true
    }

    Write-Host "  关闭 Docker Desktop..." -ForegroundColor Cyan
    # 先关 UI 主程序(触发其自身的退出清理流程), 再兜底结束后端进程
    $procs = @("Docker Desktop", "com.docker.backend", "com.docker.build", "com.docker.dev-envs")
    foreach ($name in $procs) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    # 服务层面再收一次尾(无管理员权限时失败忽略)
    Stop-Service com.docker.service -ErrorAction SilentlyContinue

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        if (-not (Test-DockerEngine)) {
            Write-Host "  Docker 引擎已停止" -ForegroundColor Green
            return $true
        }
    }

    Write-Host "  ❌ 等待超时，Docker 引擎仍在运行，请手动检查。" -ForegroundColor Red
    return $false
}

# --------------------------------------------------------
# 主流程: 确保引擎就绪, 返回 $true/$false
# --------------------------------------------------------
function Ensure-Docker {
    param([int]$TimeoutSeconds = 90)

    if (Test-DockerEngine) {
        Write-Host "  Docker 引擎已在运行" -ForegroundColor Green
        return $true
    }

    Write-Host "  Docker 引擎未运行，尝试启动..." -ForegroundColor Yellow

    # Docker Desktop 服务无管理员权限通常启动不了, 先试一次(失败忽略),
    # 真正的提权由 Docker Desktop 应用自己完成
    Start-Service com.docker.service -ErrorAction SilentlyContinue
    if (Test-DockerEngine) {
        Write-Host "  Docker 引擎已就绪" -ForegroundColor Green
        return $true
    }

    if (-not (Start-DockerDesktop)) {
        Write-Host "  ❌ 未找到 Docker Desktop，请确认已安装。" -ForegroundColor Red
        return $false
    }

    Write-Host ("  等待引擎就绪 (最长 {0} 秒)..." -f $TimeoutSeconds) -ForegroundColor DarkGray
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        if (Test-DockerEngine) {
            Write-Host "  Docker 引擎已就绪" -ForegroundColor Green
            return $true
        }
    }

    Write-Host "  ❌ 等待超时，Docker 引擎未就绪。请手动启动 Docker Desktop 后重试。" -ForegroundColor Red
    return $false
}

# 直接运行: -Stop 关闭引擎; 否则确保引擎就绪
if ($Stop) {
    if (-not (Stop-DockerDesktop -TimeoutSeconds $TimeoutSeconds)) { exit 2 }
    exit 0
}
if (-not (Ensure-Docker -TimeoutSeconds $TimeoutSeconds)) { exit 2 }
exit 0
