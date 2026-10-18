<!-- more -->

## 一、 技能简介

以品牌化风格（Editorial 设计系统）绘制图表，输出单个自包含的 HTML + SVG 文件，无阴影、无 Mermaid 风格的模板感。支持 45 类图表，包括架构图、流程图、时序图、状态机、ER/数据模型、甘特图、象限图、鱼骨图、Wardley 地图等，并支持 `.drawio`、Mermaid、`.excalidraw` 文件导入，以及导出为 PNG / SVG。

## 二、 来源与版本记录

本技能从外部仓库拉取，以下信息用于后续更新追溯：

| 项目 | 内容 |
|:-----|:-----|
| 原仓库 | https://github.com/cathrynlavery/diagram-design |
| 拉取提交 | `550fd66edff058bc73056c3416b76d69cfe865ba` |
| 提交信息 | chore(release): bump plugin manifests to 2.6.110 |
| 提交日期 | 2026-10-16 |
| 拉取日期 | 2026-10-18 |
| 技能版本 | 2.6（见 `SKILL.md` 的 metadata.version） |
| 许可证 | MIT（见本目录 [LICENSE](./LICENSE)） |

原仓库为插件形态仓库，技能本体位于其内层 `skills/diagram-design/` 目录，拉取时仅提取了该目录（外层的 docs、commands 等插件壳文件未包含）。

## 三、 目录结构

- `SKILL.md`：技能入口说明
- `assets/`：217 个图表模板 HTML
- `references/`：63 个图表类型参考文档
- `scripts/`：辅助脚本

## 四、 更新方法

（1）克隆原仓库最新版本到临时目录，获取新的提交哈希：

```bash
git clone --depth 1 https://github.com/cathrynlavery/diagram-design /tmp/diagram-design
git -C /tmp/diagram-design log -1 --format="%H %ci %s"
```

（2）用新版本的内层 `skills/diagram-design/` 覆盖本目录（保留本文件与 LICENSE）。

（3）更新本文件第二节表格中的提交哈希与日期。

（4）以上步骤已固化为自动任务：`.cnb.yml` 中 `main` 分支的 `crontab: 0 9 * * 1`（每周一 09:00，Asia/Shanghai）调用 `.cnb/scripts/sync-diagram-design.sh`，比对上游最新提交，有更新则覆盖本目录（保留 `README.md` 与 `LICENSE`）、回写第二节表格与目录统计，并按 `ci(skills/diagram-design): 同步上游 <旧哈希> → <新哈希>` 提交推送；推送后由仓库的 `push` 流水线同步到 GitHub 镜像。

本地手动执行（`--dry-run` 只报告差异，`--no-push` 只提交不推送），也可在 `main` 分支详情页点「同步 diagram-design 上游」按钮触发同一条流水线（勾选「试运行」只看差异）：

```bash
bash .cnb/scripts/sync-diagram-design.sh --dry-run
```

---
*本文档由 markdowncli 技能辅助生成*
