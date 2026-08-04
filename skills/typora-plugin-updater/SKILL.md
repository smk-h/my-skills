---
name: typora-plugin-updater
description: 为 Windows 版 Typora 安装/升级 obgnail/typora_plugin 插件（含 Typora 升级后插件失效的修复）。处理 GitHub 直连失败、UAC 提权闪退、robocopy 覆盖用户配置等问题。用于"安装 typora 插件"、"升级 typora_plugin"、"typora 右键菜单没了"、"插件失效"、"修复 typora 插件"、"typora_plugin"等场景。
---

# Skill: Typora Plugin 安装与升级

为 Windows 版 Typora 安装或升级 [obgnail/typora_plugin](https://github.com/obgnail/typora_plugin) 插件。本 skill 已固化实战中踩过的坑，可直接重复运行。

## 何时触发

当用户提出以下请求时激活：

- "帮我安装 typora 插件"、"安装 typora_plugin"
- "升级 typora 插件"、"更新插件到最新版"
- "typora 升级后右键菜单没了"、"插件失效了"、"常用插件菜单不见了"
- "修复 typora 插件"

## 背景知识

插件通过在 `window.html` 注入 `<script src="./plugin/index.js">` 生效。**Typora 自身升级会覆盖 `window.html`**，导致注入丢失、插件失效——这是最常见的"返修"场景，处理方式与全新安装几乎相同（plugin 目录还在，只需重新注入）。

用户自定义数据保存在三处，升级时必须保留：

- `plugin/global/settings/settings.user.toml` — 插件全局配置（如 auto_number 编号规则）
- `plugin/global/settings/custom_plugin.user.toml` — 自定义插件开关
- `plugin/global/user_space/` 与 `plugin/global/user_styles/` — 用户自写插件与样式

## 工作流程

### 第 1 步：探测 Typora 安装位置与现有状态

正式版与免费版目录结构不同，以 `window.html` 所在目录为准：

```bash
# Git Bash 下探测（也可用 PowerShell Test-Path）
for p in "/c/Program Files/Typora" "/c/Program Files (x86)/Typora" \
         "$LOCALAPPDATA/Programs/Typora"; do
  if [ -d "$p/resources" ]; then
    echo "FOUND: $p/resources"
    ls "$p/resources/window.html" 2>/dev/null && echo "正式版(appsrc 结构)"
    ls "$p/resources/app/window.html" 2>/dev/null && echo "免费版(app 结构)"
  fi
done
```

然后判断三项现状，决定是全新安装、升级还是修复：

1. `resources/plugin/` 是否存在 → 是否装过
2. `window.html` 是否含 `plugin/index.js` → 注入是否还在
3. `settings.user.toml` 大小 → 是否有需保留的用户配置（非空即有）

### 第 2 步：获取最新版本

优先查 release 拿最新版本号：

```bash
curl -sL "https://api.github.com/repos/obgnail/typora_plugin/releases/latest" | grep tag_name
```

### 第 3 步：下载源码（关键：网络途径选择）

⚠️ **国内环境 `github.com` 直连常超时**，但 `git clone` 和 `raw.githubusercontent.com` 通常可用。按以下顺序尝试，第一个成功即用：

```bash
# 方式 A（推荐）：git clone 指定 tag，结构完整
cd "$TEMP"
git clone --depth 1 --branch <版本号> https://github.com/obgnail/typora_plugin.git typora_plugin_src

# 方式 B：curl 下 zip（需能连 github.com，国内常失败）
curl -L --fail -o plugin.zip "https://github.com/obgnail/typora_plugin/releases/download/<版本号>/typora-plugin@v<版本号>.zip"

# 方式 C：用 WebFetch / web-reader 工具间接获取（只读，仅用于查文档）
```

下载后校验：`typora_plugin_src/plugin/index.js` 存在即结构正确。

### 第 4 步：准备 staging 目录并合并用户配置

把新版 `plugin/` 复制到 staging 目录，**并把现有用户配置覆盖进去**（双保险，即便提权脚本内的保护逻辑也能对得上）：

```bash
SRC="$TEMP/typora_plugin_src/plugin"
STAGING="$TEMP/typora_plugin_staging"
rm -rf "$STAGING"
cp -r "$SRC" "$STAGING"
# 若存在旧配置，合并到 staging
EXISTING="/c/Program Files/Typora/resources/plugin/global/settings/settings.user.toml"
[ -f "$EXISTING" ] && cp "$EXISTING" "$STAGING/global/settings/"
```

### 第 5 步：备份（必做，保命步骤）

在动 Typora 目录前，完整备份现有 plugin 目录、用户配置、window.html：

```bash
BACKUP="$TEMP/typora_plugin_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP"
P="/c/Program Files/Typora/resources"
cp -r "$P/plugin" "$BACKUP/plugin_old"
cp "$P/plugin/global/settings/settings.user.toml" "$BACKUP/" 2>/dev/null
cp "$P/window.html" "$BACKUP/window.html.before_install"
```

备份用于第 7 步验证失败时回滚，**验证全部通过后会在第 8 步自动删除**，无需用户手动清理。

### 第 6 步：UAC 提权运行安装

⚠️ **核心坑点，必读**，否则会反复"闪退"失败：

1. **不要调用官方 `plugin/bin/install_windows.ps1`**。该脚本在第 6-29 行做了自我提权（`Start-Process -Verb RunAs`），但当它已经被 UAC 提权进程调用时，管理员上下文里再次 `RunAs` 会触发异常，**窗口瞬间关闭（闪退），退出码 -196608**，且不留任何日志。本 skill 自带的 `scripts/install_elevated.ps1` 已规避此问题，是自包含版本。

2. **路径要用绝对 Windows 路径**。Git Bash 的 `$TEMP`（=`/tmp`）映射到 `C:\Users\<用户>\AppData\Local\Temp`，与 PowerShell 的 `$env:TEMP` 在非提权时一致，但**提权后管理员的 `$env:TEMP` 可能变为 `C:\Windows\Temp`**。所以日志路径和脚本路径都不能依赖 `$env:TEMP`，要用 `cygpath -w` 转成绝对路径传进去。

3. **UAC 弹窗需用户点击**。`Start-Process -Verb RunAs` 会弹出用户账户控制窗口，必须提示用户点【是】。若返回退出码 -196608 = 用户取消或被拦截。

运行方式（Git Bash 调 PowerShell 提权）：

```bash
# 脚本和日志都用绝对 Windows 路径
SCRIPT_WIN=$(cygpath -w "$TEMP/typora_plugin_install_elevated.ps1")
STAGING_WIN=$(cygpath -w "$STAGING")
LOG_WIN=$(cygpath -w "$TEMP/typora_plugin_install.log")

# 复制本 skill 的提权脚本到 TEMP
cp "<skill目录>/scripts/install_elevated.ps1" "$TEMP/typora_plugin_install_elevated.ps1"

# 清旧日志
rm -f "$TEMP/typora_plugin_install.log"

# 提权运行（用户需点 UAC 的【是】）
powershell -NoProfile -Command "
  \$p = Start-Process powershell.exe \
    -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"$SCRIPT_WIN\" -StagingDir \"$STAGING_WIN\" -LogPath \"$LOG_WIN\"' \
    -Verb RunAs -PassThru -Wait -ErrorAction Stop
  Write-Output ('退出码: ' + \$p.ExitCode)
"

# 读日志确认结果
cat "$TEMP/typora_plugin_install.log"
```

`scripts/install_elevated.ps1` 内部完成 7 步：关 Typora → 备份用户配置 → robocopy 同步 → 恢复用户配置 → 注入 window.html → 设 Users 权限 → 校验。日志末尾有 `SUCCESS` 或 `FAILED`。

### 第 7 步：独立验证（不靠安装日志）

安装脚本说成功还不够，要独立复核关键点：

```bash
P="/c/Program Files/Typora/resources"
# 1. 注入存在
grep -c "plugin/index.js" "$P/window.html"   # 应 >= 1
# 2. 用户配置未被覆盖（字节数应与备份一致）
wc -c "$P/plugin/global/settings/settings.user.toml"
# 3. 新版插件就位（抽查几个新增插件）
ls "$P/plugin/" | wc -l
```

⚠️ **若 `settings.user.toml` 字节数小于备份**（常见为 29 字节的默认空配置），说明被 robocopy `/MIR` 覆盖了——立即从第 5 步的备份恢复：

```bash
cp "$BACKUP/settings.user.toml.bak" "$P/plugin/global/settings/settings.user.toml"
# 用 md5sum 双向比对确认一致
md5sum "$P/plugin/global/settings/settings.user.toml" "$BACKUP/settings.user.toml.bak"
```

恢复无需提权（第 6 步已给 Users 赋 FullControl）。

### 第 8 步：清理与收尾

前置条件：**仅当第 7 步验证全部通过（注入存在 + 配置字节数一致 + 插件就位）才执行清理**。验证失败或做了配置恢复的，保留备份以便回滚，跳过本步的备份删除。

```bash
# 验证通过后，删除 staging、git clone 源码、临时安装脚本、备份
rm -rf "$STAGING" "$TEMP/typora_plugin_src"
rm -f  "$TEMP/typora_plugin_install_elevated.ps1" "$TEMP/typora_plugin_install.log"
rm -rf "$BACKUP"   # 仅在验证全部通过后才删
```

收尾告知用户：重启 Typora，正文区右键见"常用插件"即成功。

## 常见陷阱

- **官方 install_windows.ps1 在提权上下文里闪退**：它自我提权的逻辑在已是管理员时会异常。永远用本 skill 的 `scripts/install_elevated.ps1`，不要嵌套调用官方脚本。
- **robocopy `/MIR` 覆盖用户配置**：镜像模式以源为准，会把 `settings.user.toml` 还原成新版默认值。提权脚本内已做"robocopy 前备份、后恢复"，但 staging 准备阶段也应把用户配置拷进 staging 双保险。第 7 步必须独立校验配置字节数。
- **UAC 退出码 -196608**：用户点了取消，或被安全软件拦截。区别方法——跑一个只写标记文件的最小提权测试，看 `C:\Users\Public\` 下标记文件是否生成：生成了说明 UAC 通，闪退是脚本问题；没生成说明 UAC 被拦截。
- **Git Bash `$TEMP` vs PowerShell `$env:TEMP` vs 管理员 `$env:TEMP`**：三者可能不同。传给提权进程的所有路径一律用绝对 Windows 路径（`cygpath -w` 转换），不要依赖任何 TEMP 变量。
- **Typora 正在运行导致文件占用**：提权脚本第 1 步会强制关闭 Typora，无需用户手动关。
- **Typora 再次升级后插件失效**：Typora 升级会覆盖 `window.html` 抹掉注入。重跑本 skill 即可（plugin 目录通常还在，主要是重新注入）。也可用插件自带的 updater（右键 → 少用插件 → 升级插件）。
