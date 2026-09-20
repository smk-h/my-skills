---
name: mist-docs
description: 在 mist 文档库中按 tdoc 工作流创建或整理文档：新建文章、章节目录、index.md 目录页、添加 frontmatter、维护 path-map.js 英文路径映射。当用户明确提到 mist 文档库、tdoc、sdoc 时使用；用户未指明 mist 文档库时按普通 Markdown 文档处理，不触发本技能。
---

# 在 mist 文档库中创建文档（tdoc 工作流）

mist 文档库依赖 tdoc CLI（`@docs-site/tdoc-cli`）生成带唯一 permalink 的 frontmatter。**不要手写 frontmatter**——permalink 是时间戳与 UUID 算出来的 24 位 hex，手写无法保证唯一性。正确做法：先用 tdoc 生成文档骨架，再用编辑工具填写正文。

**总原则**：所有带 `-m` 的命令都要求 `path-map.js` 是当前目录结构的最新映射。因此固定顺序永远是"先定目录结构 → `m:m` 更新映射并改 default → 最后创建文档"，下面三个场景都遵守这一顺序。

## 1. 识别文档库（守卫步骤）

动手前先确认目标库的根目录（通常是 `docs/`，即 package.json / .vitepress 所在目录）。满足以下任一特征即为 mist 文档库：

- 存在 `docs/src/sdoc`（或 `src/sdoc`）目录；
- 或现有 md 文档的 frontmatter 带 `tdoc:` 块（detailDate / fulluuid / useduuid）；
- 或用户明确说明这是 mist / tdoc 文档库。

**都不满足则不是 mist 文档库：停止使用本技能，按普通 Markdown 文档流程处理。** `sdoc/path-map.js` 不要求已存在——新库没有映射文件是正常状态，走场景 3 初始化。

```text
docs/                      ← 文档库根（命令在这里执行）
└── src/
    ├── .vitepress/
    ├── sdoc/
    │   ├── path-map.js    ← 中文目录名 → 英文别名映射（新库可能尚无此文件，由 m:m 生成）
    │   ├── 01-开发/
    │   │   ├── index.md   ← 目录页
    │   │   └── LV001-xxx.md
    │   └── 02-组件/
    └── index.md
```

## 2. 命名与结构规则

- 章节目录：`NN-中文名`（如 `03-插件`）。
- 文章：`LVxxx-标题.md`，三位零填充编号，组内独立编号，**所有目录一律如此，老目录追加也不例外**。统一采用步长 3 的间隔编号（LV001、LV004、LV007……），目的是给后续插入文档留空号；**同一目录下不同主题用间隔 30 的号段分区**（主题 A 从 LV010 起、主题 B 从 LV040 起、主题 C 从 LV070 起……主题内仍步长 3，每个号段约容 7 篇加插入空号）。
- 编号宽度固定三位：导航/侧边栏/目录页按文件名字典序排列，三位零填充才能保证字典序 = 数值序（上限 LV999）。目录内若还有历史遗留的两位编号（LV01），新文档仍强制用三位，旧文档建议按第 6 节场景 4 批量迁移，避免混排乱序。
- 插入文档时优先占用相邻文章之间的空号（这正是留间隔的目的）；号段耗尽需要整体重排时，重命名走第 6 节场景 4 的注意事项。
- 每个内容目录必须有 `index.md`（VitePress 目录访问需要默认页，且 mist 主题靠它的 `catalogue: true` + `path` 生成目录数据），必须由 `tdoc m:n index` 生成。
- 豁免（不需要 index.md）：`img/` 图片目录、与 md 同名的附件目录（如 `LV006-xxx.md` 对应的 `LV006-xxx/img/`）、`@pages`、`test`。
- 目录页与文章使用不同模板：`index` 模板（layout: page + catalogue: true + path，title 自动去掉目录序号前缀）；`post` 模板（index: true + 文章字段）。tdoc 按文件名是否为 `index` 自动选择。

## 3. 场景 1：新建目录并创建文档

（目录已存在、映射已就绪时，直接从第 4 步开始。）

```bash
cd <文档库根>   # 通常是 docs/

# 1. 新建目录
mkdir -p "src/sdoc/03-插件/01-独立插件包"

# 2. 更新映射（-d 必须指向 sdoc 目录本身，否则会写到 src/path-map.js）
tdoc m:m -d src/sdoc

# 3. 编辑 src/sdoc/path-map.js，把新目录的 "default" 改成英文别名（小写 + 连字符）
#    "01-独立插件包": "default",  →  "01-独立插件包": "standalone-plugin",

# 4. 生成目录页 index.md
tdoc m:n index -d "src/sdoc/03-插件/01-独立插件包" -m

# 5. 创建文章（编号按第 2 节规则先确定）
tdoc m:n "LV004-文章标题" -d "src/sdoc/03-插件/01-独立插件包" -m
```

- **第 3 步不能省**：实测映射值还是 `default` 时 `m:n -m` 不会报错，而是静默生成 `/sdoc/default/<hex>` 这种错误前缀的 permalink，事后只能手改；没有映射的目录则直接失败（`❌ 路径部分'xx'没有有效的映射`）。只要刚跑过 `m:m`，就必须检查新键的值。
- `m:m` 的行为：保留已有键的值、给新目录填 `default`、**删除已不存在目录的键**，所以它同时是目录结构调整后的同步手段。
- 英文别名决定 permalink 前缀（`/sdoc/<父级别名>/<本级别名>/<hex>`），拿不准就先问用户。
- `m:n` 的 `-d` 必须带（不指定时默认输出到 `./test`）；`-m` 必须带（不带时 permalink 前缀是 `/docs/`，与库内其他文档不一致）；中文路径要加引号。
- 目标文件已存在时会交互式询问是否覆盖，非交互环境下会卡住——选新文件名，或确认覆盖时加 `-f`。
- 生成后用 Write/Edit 工具在 frontmatter 之后填写正文（模板尾部有 `<!-- more -->` 摘要分隔符）。

## 4. 场景 2：为已存在目录的文档补 frontmatter

```bash
tdoc m:a "src/sdoc/03-插件/某文档.md" -m     # 单个文件
tdoc m:a "src/sdoc/03-插件" -d -m            # -d 批量处理目录内所有 md
```

- 直接执行即可：已有 frontmatter 的文件会跳过（提示"文件已包含frontmatter"），命令是幂等的。
- `-m` 同样要求映射就绪：老目录通常已有映射；若刚建过目录，先回场景 1 完成第 2、3 步。

## 5. 场景 3：新文档库初始化

前提：VitePress 项目已就绪（存在 `src/` 与 `.vitepress/`）。`m:n -m` 默认读取的是 `sdoc/path-map.js`，而 `m:m` 只有在扫描目标是 `sdoc` 目录时才会把映射写在那里——所以**必须先建 `sdoc` 目录再跑 `m:m`**：

```bash
cd <新文档库根>

# 1. 创建 sdoc 根目录，并把首批章节目录一并建好（一次 m:m 全部登记）
mkdir -p src/sdoc "src/sdoc/01-开发" "src/sdoc/02-组件"

# 2. 生成映射
tdoc m:m -d src/sdoc

# 3. 编辑 src/sdoc/path-map.js，把所有键的 "default" 改成英文别名
#    （首次生成时全部是 default，一个不落全部要改）

# 4. 回到场景 1 的第 4、5 步：逐目录生成 index.md 和文章
```

注意：若只建了 `src/` 没建 `sdoc/` 就跑 `m:m`，映射会被写到 `src/path-map.js`（错误位置，实测如此），后续 `m:n -m` 找不到默认映射文件。建好首批章节目录再一次性 `m:m`，比"每建一个目录跑一次"更省事；之后再新增目录走场景 1。

## 6. 场景 4：移动或重命名文档

- permalink 写在 frontmatter 里、由 permalink 插件按 frontmatter 解析，**移动/改名文件不影响访问地址**，frontmatter 整体保持不动。
- 需要同步的三件事：文件名改了 frontmatter 的 `title` 要一起改；存在同名资源目录（`LV006-xxx/img/`）时目录必须跟着改名，否则文内 `img/xxx.png` 引用会断；层级变化后检查文内相对链接。
- 用 `git mv` 保留历史。

## 7. 验证

```bash
tdoc m:p "src/sdoc/03-插件/LV004-xxx.md"   # 解析并打印 frontmatter 元数据
```

检查三点：permalink 前缀是预期的英文路径（不含 `default`）；目录页的 `path` 从 `sdoc` 起算（如 `sdoc/03-插件/01-独立插件包`）；文章的 `title` 与文件名一致。
