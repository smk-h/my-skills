---
name: windows-disk-analysis
description: 分析 Windows 磁盘空间占用，定位大文件和大目录，标记可安全清理的项目并生成报告。用于"C盘满了"、"磁盘空间分析"、"哪些文件可以清理"、"空间不足"、"Docker/WSL 占用大"、"大文件排查"等场景。
---

# Skill: Windows 磁盘空间分析

逐层定位磁盘大头，避免全盘递归扫描超时。

## 何时触发

当用户提出以下类型请求时激活：

- "C 盘满了"、"空间不足"
- "磁盘空间分析"、"磁盘清理"
- "哪些文件 / 文件夹可以清理"
- "Docker / WSL 占了好大空间"
- "排查大文件"、"为什么 C 盘这么大"

## 工作流程

### 1. 查看磁盘整体使用

```powershell
Get-PSDrive C | Select-Object Used,Free,
  @{N='UsedGB';E={[math]::Round($_.Used/1GB,2)}},
  @{N='FreeGB';E={[math]::Round($_.Free/1GB,2)}}
```

### 2. 定位用户目录大头（快速）

先用一次递归判断空间被用户配置文件的哪一块吃掉（AppData、Documents、Downloads、OneDrive 等），再决定下钻方向。仅扫单个用户目录，比扫整个 C:\ 快很多；只想找缓存可跳过本步直接进第 3 步。

```powershell
Get-ChildItem "C:\Users\$env:USERNAME" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $s = (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
    Measure-Object Length -Sum).Sum
  [PSCustomObject]@{ SizeGB = [math]::Round($s/1GB,2); Path = $_.FullName }
} | Where-Object { $_.SizeGB -gt 0.5 } |
  Sort-Object SizeGB -Descending | Select-Object -First 10 | Format-Table -AutoSize
```

### 3. 扫描常见大文件聚集目录

全盘递归扫描会超时，改为按已知热点路径逐一测量。用短超时的多组命令，而非一次全盘扫描。

```powershell
$paths = @(
  "C:\Windows\Temp",
  "C:\Windows\SoftwareDistribution\Download",
  "C:\Windows\Installer",
  "C:\Windows\Logs",
  "C:\Windows.old",
  "C:\Windows\Minidump",
  "C:\ProgramData",
  "C:\Users\$env:USERNAME\AppData\Local\Temp",
  "C:\Users\$env:USERNAME\Downloads",
  "C:\Users\$env:USERNAME\AppData\Roaming",
  "C:\Users\$env:USERNAME\AppData\Local\Programs",
  "C:\Users\$env:USERNAME\AppData\Local\Microsoft\Windows\Explorer",
  "C:\Users\$env:USERNAME\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
  "C:\Users\$env:USERNAME\AppData\Local\Google\Chrome\User Data\Default\Cache",
  "C:\Users\$env:USERNAME\AppData\Local\npm-cache",
  "C:\Users\$env:USERNAME\AppData\Local\pip",
  "C:\Users\$env:USERNAME\AppData\Local\Yarn",
  "C:\Users\$env:USERNAME\AppData\Local\pnpm",
  "C:\Users\$env:USERNAME\AppData\Local\JetBrains",
  "C:\Users\$env:USERNAME\AppData\Local\Packages",
  "C:\Users\$env:USERNAME\AppData\Local\Docker",
  "C:\Users\$env:USERNAME\.nuget\packages",
  "C:\Users\$env:USERNAME\.cache"
)
foreach ($p in $paths) {
  if (Test-Path $p) {
    $item = Get-Item $p -Force
    if ($item.PSIsContainer) {
      $size = (Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    } else { $size = $item.Length }
    $sizeMB = [math]::Round($size/1MB,1)
    if ($sizeMB -gt 1) { Write-Output "$sizeMB MB`t$p" }
  }
}
```

规则：`-gt 1` 过滤琐碎项，按 MB 输出便于排序。

### 4. 逐层深入大目录

对第 3 步发现的大目录(>1GB)继续下钻一层，测量子目录大小。重复此过程直到定位到具体缓存文件夹。

```powershell
# 将 $bigDir 替换为第 3 步发现的大目录路径
$bigDir = "C:\Users\$env:USERNAME\AppData\Local\Microsoft"
Get-ChildItem $bigDir -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $s = (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
    Measure-Object Length -Sum).Sum
  [PSCustomObject]@{ SizeMB = [math]::Round($s/1MB,1); Path = $_.FullName }
} | Where-Object { $_.SizeMB -gt 100 } |
  Sort-Object SizeMB -Descending | Select-Object -First 12 | Format-Table -AutoSize
```

典型下钻路径链：

- Edge 缓存：`AppData\Local`(18GB) → `Microsoft`(16.7GB) → `Edge\User Data\Default`(16GB) → `Service Worker\CacheStorage`(13.9GB)
- WSL2 虚拟磁盘：`AppData\Local\Packages`(50GB) → `CanonicalGroupLimited.Ubuntu_*`(49GB) → `LocalState\ext4.vhdx`(48GB)。`.vhdx` 可用 `wsl --shutdown` 后经 `diskpart` 的 `compact vdisk` 压缩回收，不要直接删。
- Docker：`AppData\Local\Docker`(40GB) → `wsl\disk\docker_data.vhdx`(39GB)

> 对单个超大目录（几十万文件），`Get-ChildItem -Recurse | Measure-Object` 会很慢。可用 robocopy 只读遍历替代：`robocopy $bigDir C:\__dummy__ /L /S /NJH /BYTES`，输出末尾的 `Bytes` 行即为该目录总字节，比 PowerShell 快很多且自动跳过权限错误。

### 5. 检查系统大文件

系统文件用 `dir /a` 显示隐藏文件，PowerShell 的 `Get-Item` 对 `hiberfil.sys` 等可能返回 0。

```powershell
cmd /c "dir C:\hiberfil.sys C:\pagefile.sys C:\swapfile.sys /a"
```

常见系统大文件：`hiberfil.sys`(休眠文件)、`pagefile.sys`(虚拟内存)、`swapfile.sys`(UWP交换)。

### 6. 检查回收站

```powershell
$r = (Get-ChildItem "C:\`$Recycle.Bin" -Recurse -File -Force -ErrorAction SilentlyContinue |
  Measure-Object Length -Sum).Sum
Write-Output ("{0} MB`tC:\`$Recycle.Bin" -f [math]::Round($r/1MB,1))
```

### 7. 列出 Downloads 中的大文件

```powershell
Get-ChildItem "C:\Users\$env:USERNAME\Downloads" -File -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.Length -gt 50MB } |
  Sort-Object Length -Descending |
  Select-Object @{N='SizeMB';E={[math]::Round($_.Length/1MB,1)}}, FullName -First 15 |
  Format-Table -AutoSize
```

## 可清理项目分类

按风险从低到高分四档。

### 强烈推荐（低风险，典型可释放 15-20GB）

| 项目 | 路径 | 清理方式 |
|------|------|----------|
| 浏览器 Service Worker 缓存 | `AppData\Local\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage` | 浏览器设置内清除缓存，或关闭浏览器后删文件夹 |
| 浏览器 Cache / Code Cache | `...\Edge\...\Default\Cache`、`...\Default\Code Cache` | 同上 |
| 回收站 | `C:\$Recycle.Bin` | 右键清空 |
| 系统临时文件 | `AppData\Local\Temp`、`C:\Windows\Temp` | 磁盘清理工具或手动删 |
| 软件分发下载缓存 | `C:\Windows\SoftwareDistribution\Download` | 停止 Windows Update 服务后删 |
| 升级残留 | `C:\Windows.old` | 磁盘清理勾选"以前的 Windows 安装"，确认无需回退后清理 |
| 包管理器缓存 | `AppData\Local\npm-cache`、`pip`、`Yarn`、`pnpm` | `npm cache clean --force`、`pip cache purge`、`pnpm store prune` |
| 内存转储 | `C:\Windows\Minidump`、`C:\Windows\MEMORY.DMP` | 排查完问题后删除 |

### 推荐（中风险）

| 项目 | 路径 | 清理方式 |
|------|------|----------|
| VS Code 缓存 | `AppData\Roaming\Code` 下的 `Cache`、`CachedData` | 关闭 VS Code 后删除缓存子目录 |
| JetBrains 缓存与索引 | `AppData\Local\JetBrains` | IDE 内 File → Invalidate Caches，或关闭后删 caches 子目录 |
| NuGet 全局包缓存 | `.nuget\packages` | `dotnet nuget locals all --clear`（删后下次还原会重下） |
| 百度网盘缓存 | `AppData\Roaming\baidunetdisk` | 应用内清理 |
| Explorer 缩略图缓存 | `AppData\Local\Microsoft\Windows\Explorer` | 磁盘清理工具勾选"缩略图" |

### 需注意风险

| 项目 | 路径 | 注意事项 |
|------|------|----------|
| Windows Installer | `C:\Windows\Installer` | 含卸载/修复补丁，勿手动删，用 PatchCleaner 识别孤立补丁 |
| 应用用户数据 | `AppData\*` 下各应用目录 | 优先在应用内"清除缓存"，别直接删整个目录 |
| 聊天记录 | `AppData\Roaming\Tencent` | 含聊天文件，应用内清理更安全 |
| WSL2 / Docker 虚拟磁盘 | `...\Packages\*\LocalState\ext4.vhdx`、`...\Docker\wsl\disk\docker_data.vhdx` | 不要直接删，先在发行版内清理，再 `wsl --shutdown` + `diskpart` 压缩 vhdx |

### 系统级操作（高影响）

| 项目 | 大小 | 操作 |
|------|------|------|
| `hiberfil.sys` | 6-13GB | 管理员运行 `powercfg /hibernate off`，代价是失去休眠功能 |
| `pagefile.sys` | 2-8GB | 系统属性→高级→虚拟内存中调小或移到其他盘 |

## 报告生成

将结果整理为给用户的报告，结构：

1. 磁盘空间概览（总量/已用/剩余/占比）
2. 大空间占用排名表（从大到小）
3. 可清理项目分档表（标明释放空间和清理方式）
4. 给出"低风险三项即可释放 X GB"的快速建议
5. **清理前确认**：列出建议删除项及预估释放量，等用户明确确认后再执行删除；涉及应用数据时优先建议"应用内清除缓存"而非直接删目录

## 常见陷阱

- `Get-ChildItem C:\ -Recurse` 全盘扫描必然超时，改用分层热点扫描
- `hiberfil.sys` 等隐藏系统文件需用 `dir /a`，`Get-Item` 可能返回 0
- 删除浏览器缓存前务必关闭对应浏览器，否则文件被占用无法删除
- 多用户或以管理员身份运行时，`$env:USERNAME` 可能不是真正占空间的账户，必要时用 `Get-ChildItem C:\Users\* -Directory` 逐个用户测量
- `.vhdx`（WSL2 / Docker）膨胀后即使内部删了文件也不会自动缩小，需单独压缩
