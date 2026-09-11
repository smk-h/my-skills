# 苏木的 AI skills

## Skills 索引

skills目录包含技能集合，每个子目录为一个独立技能。

| 技能 | 说明 |
|:------|:------|
| [c-lang-spec](./skills/c-lang-spec/SKILL.md) | C 语言编程规范的代码检查与格式化指导 |
| [code-spec](./skills/code-spec/SKILL.md) | Spec 驱动开发：依次生成 spec/plan/task/checklist 四份文档，指导开发与验收 |
| [makefile-spec](./skills/makefile-spec/SKILL.md) | Makefile 编写规范的代码检查、格式化与编写指导 |
| [markdowncli](./skills/markdowncli/SKILL.md) | 按指定规范创建或者修改 markdown 文件 |
| [plantuml-diagram](./skills/plantuml-diagram/SKILL.md) | 用 PlantUML 画架构图/时序图/流程图并转 SVG 嵌入文档，固化在线渲染的中文/皮肤/布局避坑方案，自带 render-puml.mjs |
| [excalidraw-diagram](./skills/excalidraw-diagram/SKILL.md) | 用 Excalidraw 绘制可自由拖拽编辑的手绘风格配图，自带渲染与校验脚本 |
| [ts-lang-spec](./skills/ts-lang-spec/SKILL.md) | TypeScript 语言编程规范的代码检查与格式化指导 |
| [git-commit-spec](./skills/git-commit-spec/SKILL.md) | Git 提交规范的检查、格式化与编写指导，基于 Conventional Commits 规范 |
| [typora-plugin-updater](./skills/typora-plugin-updater/SKILL.md) | 为 Windows 版 Typora 安装/升级 typora_plugin 插件，处理 GitHub 直连失败、UAC 提权闪退、配置覆盖等坑 |
| [windows-disk-analysis](./skills/windows-disk-analysis/SKILL.md) | 分析 Windows 磁盘空间占用，定位大文件与大目录，标记可安全清理项并生成报告 |


## 二、安装skills

skills 以软链接方式安装到各 AI 扩展：skills 只存一份，各工具通过链接共享，改仓库即全员生效。
Windows 下使用 `windows-skills.ps1`（Junction，无需管理员权限），Linux / macOS 下使用 `linux-skills.sh`（符号链接 `ln -s`）。

### 1. 使用仓库脚本安装（推荐）

软链接方案通过 `~/.smskills` 本地镜像层，解耦仓库路径与 agent 链接：

```
仓库 skills/  ──[update]──▶  ~/.smskills/  ──[link]──▶  各 agent 工具
```

仓库挪动后只需重新 `update`，agent 链接不会断。

**Windows**（使用 `windows-skills.ps1`，通过 Junction，无需管理员权限）：

```powershell
./windows-skills.ps1 -install         # 首次安装：镜像 + 全员链接
./windows-skills.ps1 -update          # 仓库改动后刷新本地镜像（agent 即时生效）
./windows-skills.ps1 -status          # 查看链接矩阵
./windows-skills.ps1 -link claude     # 仅链接 Claude Code
./windows-skills.ps1 -unlink roo      # 删除 RooCode 的链接（仅删链接，源不动）
```

**Linux / macOS**（使用 `linux-skills.sh`，通过符号链接 `ln -s`）：

```bash
./linux-skills.sh install             # 首次安装：镜像 + 全员链接
./linux-skills.sh update              # 仓库改动后刷新本地镜像
./linux-skills.sh status              # 查看链接矩阵
./linux-skills.sh link claude         # 仅链接 Claude Code
./linux-skills.sh unlink roo          # 删除 RooCode 的链接
```

| 命令 | 作用 |
|:-----|:-----|
| `install` / `-install` | 一键安装：`update` + `link all` |
| `update` / `-update` | 把仓库 `skills/` 镜像覆盖到 `~/.smskills`（含孤儿清理） |
| `link [tool] [force]` | 把 `~/.smskills/<skill>` 链接到各 agent 工具 |
| `unlink [tool]` | 删除工具的链接（仅删链接，`~/.smskills` 源不动） |
| `list` / `-l` | 列出已安装 skills（带 link/copy 标记） |
| `status` / `-status` | 显示链接状态矩阵 |

> 支持的 agent 工具：`claude`、`roo`、`zcode`、`opencode`、`codebuddy`、`codex`。

### 2. 使用 npx skills add 安装

通过 [skills CLI](https://github.com/vercel-labs/skills) 可一键将本仓库的技能安装到 OpenCode、Claude Code 等 AI 编程工具：

```bash
# 全局安装所有 skills
npx skills add https://cnb.cool/smk.h/my-skills.git -g

# 全局安装到指定工具
npx skills add https://cnb.cool/smk.h/my-skills.git -g -a opencode
npx skills add https://cnb.cool/smk.h/my-skills.git -g -a claude-code
npx skills add https://cnb.cool/smk.h/my-skills.git -g -a opencode -a claude-code -a roo

# 安装指定 skill（全局）
npx skills add https://cnb.cool/smk.h/my-skills.git -g --skill markdowncli

# 预览可安装的 skills 列表
npx skills add https://cnb.cool/smk.h/my-skills.git --list

# 一键安装全部 skills 到全部工具（无交互）
npx skills add https://cnb.cool/smk.h/my-skills.git -g --all
```

| 选项 | 说明 |
| ---- | ---- |
| `-g, --global` | 安装到用户全局目录（`~/`），而非当前项目目录 |
| `-a, --agent` | 指定目标工具（`opencode`、`claude-code`、`roo` 等） |
| `-s, --skill` | 指定安装特定 skill，`'*'` 表示全部 |
| `--all` | 安装全部 skills 到全部已检测到的工具 |
| `-y, --yes` | 跳过确认提示，直接安装 |

## 三、测试

`test/` 目录提供安装脚本的端到端测试，覆盖全部命令并校验安全性不变量（仓库源全程不被破坏、mirror 不被误删）。技能数量动态扫描，增删 skill 无需改测试代码。

```powershell
# Windows：测试 windows-skills.ps1
./test/test-windows-skills.ps1

# Windows：测试 linux-skills.sh（通过 docker + ubuntu:22.04，无需 Git Bash）
./test/test-linux-skills.ps1
```

```bash
# Linux / macOS：直接测试 linux-skills.sh
./test/test-linux-skills.sh
```

---
*本文档由 markdowncli 技能辅助生成*
