# 苏木的 AI skills

## 一、Windows

使用 `install.ps1` 管理 skills 的安装、删除和列表：

```powershell
# 显示帮助
./install.ps1 -h

# 列出所有已安装的 skills
./install.ps1 -l

# 安装 skills 到指定工具（claude/opencode/roo/all）
./install.ps1 -add roo           # 安装到 Roo，已存在时询问是否覆盖
./install.ps1 -add roo -f        # 强制覆盖，不询问
./install.ps1 -add all -f        # 强制覆盖安装到所有工具

# 删除指定工具的所有 skills（claude/opencode/roo/all）
./install.ps1 -d claude          # 删除 Claude Code 的 skills
./install.ps1 -d all             # 删除所有工具的 skills
```

> **注意**：`install.ps1` 含中文注释，PowerShell 5.1 需要 UTF-8 BOM 才能正确解析。如果脚本被其他编辑器重新保存，请确保保留 UTF-8 BOM 编码（文件开头 3 字节 `EF BB BF`）。

## 二、Linux / macOS

使用 `install.sh` 管理 skills 的安装、卸载和状态查看：

```bash
# 无参数运行进入交互式菜单
./install.sh

# 安装（旧版命令，兼容保留）
./install.sh all          # 安装到所有 AI 扩展
./install.sh roocode      # 安装到 RooCode    (~/.roo/skills/)
./install.sh claude       # 安装到 Claude Code (~/.claude/skills/)
./install.sh codebuddy    # 安装到 CodeBuddy  (~/.codebuddy/skills/)
./install.sh opencode     # 安装到 OpenCode    (~/.config/opencode/skills/)

# 安装（新版命令）
./install.sh install roocode           # 安装到 RooCode
./install.sh install all force         # 强制覆盖安装到所有工具

# 查看与卸载
./install.sh status                    # 显示安装状态
./install.sh list                      # 列出所有已安装的技能
./install.sh list claude               # 列出 Claude Code 的技能
./install.sh uninstall                 # 卸载所有已安装的技能（兼容旧版）
./install.sh remove all                # 卸载所有工具的技能（新版）
./install.sh help                      # 显示帮助信息
```
