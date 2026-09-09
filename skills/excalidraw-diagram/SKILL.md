---
name: excalidraw-diagram
description: 用 Excalidraw 场景 JSON 绘制可编辑的技术配图（架构图、流程图、拓扑图、示意图），并渲染成 SVG 嵌入 Markdown 文档。当需要产出用户可自由拖拽编辑的手绘风格图、需要把 graphviz 图转成可编辑形态、或需要解析/修改已有 .excalidraw 文件时使用。自带渲染与校验脚本。
---

# Excalidraw 配图

## 概述

Excalidraw 的 `.excalidraw` 文件本质是带坐标的 JSON 场景。相比 Graphviz/PlantUML 的「写代码 → 自动布局」，
Excalidraw 是「直接给出每个元素的绝对坐标」，换来的是**用户拿到图后可以自由拖拽编辑**。

本技能提供：手绘风格配图的统一皮肤、场景 JSON 的字段与绑定规则、零依赖结构校验脚本、
以及把场景渲染成 SVG 的脚本。渲染依赖装在技能目录自己的 `.render-runtime/` 下（不污染项目
`package.json`），首次渲染时自动安装，也可用 `scripts/install-deps.mjs` 单独预装。

## 目录约定

遵循「一篇文档 + 同级同名资源目录」（与 markdowncli 配合）：

约定只有一条：**md 文档在哪里，同名资源目录就在同级**（目录名 = md 文件名去掉 `.md`），
里面放源文件，其下的 `img/` 放渲染产物。不限定目录层级，项目里是 `docs/` 还是别的位置都一样：

```
某主题.md                          ← 文档正文（引用 ./某主题/img/xxx.excalidraw.svg）
某主题/                            ← 同名资源目录（与 md 同级）
  ├── xxx.excalidraw               ← 源文件（必须保留，可编辑）
  └── img/                         ← SVG 输出目录（脚本默认写这里）
      └── xxx.excalidraw.svg       ← 渲染产物（禁止手改）
```

文档中用相对路径引用：`![标题](./某主题/img/xxx.excalidraw.svg)`（相对路径从 md 所在目录起算）

## 工作流程

### 第 1 步：规划坐标布局

Excalidraw 没有自动布局，**必须先规划坐标网格**再写元素：

1. 确定图的分区：主体流程（通常左列/中列）、旁路或外围对象（通常右列/下方）
2. 为每个节点分配 `(x, y, width, height)`，注意 y 向下增大
3. 节点垂直间距建议 110-140，水平间距 150+；外框比内部元素四周多留 20-40；
   **节点之间不得重叠**（容器/分组框与组内节点除外）
4. 按「CJK 字符 ≈ 1.0 × fontSize、拉丁字符 ≈ 0.6 × fontSize」估算文字宽度，容器宽度再留 10% 余量

复杂拓扑建议先在草稿里列出每个节点的中心坐标，再换算成左上角坐标，避免边写边算导致错位。

### 第 2 步：写场景 JSON

从 `assets/template-scene.excalidraw` 复制起步（它是字段齐全的两节点 + 带标签箭头的最小样例），
再按布局增删元素。

必须遵守的规则：

- **元素顺序即层级**：先写矩形（容器/节点），再写绑定文字，最后写箭头
- **文字是独立 text 元素**，不是矩形属性；容器 `boundElements` 与文字 `containerId` **双向都要写**
- **框与框不得重叠**：部分交叠（压角/压边）必然是坐标错位，校验脚本强制拦截；
  完全包含（容器与组内节点）和相邻贴边（间隙 0）合法
- **字体用 `fontFamily: 5`**（Excalifont，当前默认）。`1`（Virgil）已废弃，不要用
- **所有元素都要带齐必填字段**：`index`、`originalText`、`autoResize` 最容易漏，完整清单见 `references/scene-format.md`
- **`seed` / `versionNonce`** 给不重复的随机整数，决定手绘抖动形状，变动会导致图形重绘
- **标签最多 2 行**，换行用 `\n`
- 配色沿用统一皮肤（见下表），与 graphviz-diagram / plantuml-diagram 保持一致

| 颜色 | 用途 |
|---|---|
| `#7A93BE` | 节点主边框色 |
| `#DCE9FB` | 浅蓝——主参与者 / 容器 / 起止节点 |
| `#DDF3E4` | 浅绿——中间层（传输 / 桥接层） |
| `#FFF3D6` | 浅黄——外部设备 / 第三方 |
| `#F7F9FC` | 极浅蓝——普通处理节点（默认） |
| `#FAFAFA` + `strokeStyle: dashed` + `#999999` | 虚线边界节点 |
| `#555555` | 默认箭头色 |
| `#2C5F8A` / `#4E7A2C` / `#8A4B2C` | 蓝 / 绿 / 棕色通路（区分不同链路） |
| `#1F2933` | 文字色 |

箭头写法要点：

- `points` 是相对 `x`/`y` 的偏移，首点必须是 `[0, 0]`；`width`/`height` 取偏移绝对值
- **箭头线体不得从框上过**：被挡住时用弧线箭头或折线箭头**绕行**，直线只许贴框边或走空白
- **弧线箭头** = 多中间点 + `roundness: {type: 2}`，按需二选一：
  - **精确弧**：按真圆弧**密集采样 10-14 个中间点**（每段转角 ≤35°，手摆稀疏点会内凹穿框，
    实测 12 点样条精确过点、误差 ±1px），端点精确 `[0,0]` / `[dx,dy]`——需要贴着指定圆弧走线时用
  - **三点甩弧**：起点边 → 外甩拐点 → 终点边共 3 点——绕过单个障碍物时用，曲线向拐角
    内侧自然收弯（实测 77° 内偏约 50px），拐点离被绕框留足余量即可，渲染后视觉验收；
    ≥4 点的多拐角配 type 2 仍会甩尾，禁用
- **折线箭头** = 多拐点 + `roundness: null`：90° 直角绕行走廊，先算拐点坐标再写 `points`
- **端点必须贴合节点边框**（贴 binding 节点自身，或「组内节点出组」时贴外层容器边框）。
  悬空或扎进框内都会让读者看不出箭头从哪指向哪；binding 有值时校验脚本会强制检查
- **端点入射/出射只禁平行，不要求正交**：首/末段与所贴边框平行（水平段贴左/右边框、
  垂直段贴顶/底边框）会让线贴着框边滑行，不美观（几何上必然共线），校验脚本强制拦截；
  **斜向成角进出完全合法**，与边框有任何非零夹角即可，90° 只是特例。选边时选面向目标的
  那条边（目标在右下，从底边或右边斜出都行），不必为凑正交绕路；一源多目标用扇形斜连，
  从同一条边的不同位置出框。拿不准入射/绕行怎么写时，打开 `assets/template-arrow-patterns.excalidraw` 对照合法形态
- 跨层长箭头优先走**空白走廊**折线路由（出框边中点 → 走廊 → 入框边中点），不要直线斜穿多个框
- 吸附可选：`startBinding`/`endBinding` 填 `{ "elementId": "r_a", "focus": 0, "gap": 4 }` 后箭头会跟随节点移动；
  手写场景允许留 `null`（拖动节点时箭头不跟随，用户可在编辑器里拖端点重新吸附）
- 箭头标签是 `containerId` 指向箭头的 text 元素，会跟随箭头移动；**标签写明主语**
  （如 `rkisp async notifier`，而不是光秃秃的 `async notifier`），同色多线时图例必须分别说明

流程图类配图（有起止/执行/判断节点）**从 `assets/template-flowchart.excalidraw` 复制起步**
（选对应子图，改文字与坐标），并遵守：

- 节点分三种：起止用浅蓝 `#DCE9FB` 圆角矩形，执行用默认 `#F7F9FC`，判断用浅黄 `#FFF3D6` 菱形
- 节点填充统一 `fillStyle: "hachure"`（内部斜线手绘风）；需要平整色块强调时再用 `"solid"`
- 判断框要宽：文字只占菱形中部内接区，宽度取文字估算宽 2 倍以上，高度约为宽度一半
- **分支必须带标签**：是/否写成箭头标签，最好带动作（如 `否（重试）`、`否（修正）`）
- **回路走侧边走廊**：从判断框侧顶点水平出，`roundness: null` 折线绕回目标**侧边框**水平汇入，
  不要斜穿主线、不要逆着主流方向从底边向上顶入
- **多框汇入同一框**：各入箭头分别落目标顶边不同位置或不同边框，入射点互不共点；
  汇入侧边框时水平入射，汇入顶边时垂直或斜向入射（禁平行）
- **多框汇集后统一汇入（总线式，如多条件选型汇总）**：各框从靠走廊一侧的边框水平出
  **无箭头短接线**（type `line`，起点绑框、终点自由接走廊）；走廊只画**一根**主干箭头
  （`roundness: null` 折线）下行后单箭头汇入终点。不要每框各画一根全程箭头叠在走廊上——
  终点会堆出多个箭头头，线也互相压叠

### 第 3 步：校验

```bash
node <skill>/scripts/validate-scene.mjs 某主题/xxx.excalidraw [--fix]
```

零依赖静态检查：必填字段、id 唯一、引用有效性、废弃字体、**框体重叠**（部分交叠，
容器包含除外）、**箭头几何**（线体穿框、拐点甩尾、端点悬空/扎入、入射方向平行贴边）、
文字可能溢出容器，自动跳过 `isDeleted`
墓碑元素。加 `--fix` 可自动补齐 `index` / `originalText` / `autoResize` /
`lastCommittedPoint` / binding 的 `focus`/`gap`，并把废弃字体改为 5。

**写完场景务必先校验再渲染**，能挡住绝大多数「编辑器打开后样式异常」的问题。

### 第 4 步：渲染成 SVG

```bash
node <skill>/scripts/render-excalidraw.mjs 某主题/xxx.excalidraw [--out-dir <dir>]
```

- 默认输出到场景文件同级的 `img/`，文件名为 `<stem>.excalidraw.svg`（刻意保留 `.excalidraw` 标识：
  同一文档可能并存同名 `.dot` 源文件，其产物是 `<stem>.svg`，不加区分会把 graphviz 版本覆盖掉）
- 需要别的名字时用 `--out-dir` 指定输出目录
- 首次运行会在技能目录的 `.render-runtime/` 下自动安装 `@excalidraw/utils@0.1.3-test32` + `jsdom`
  （约 100MB，仅本地），**不写入项目的 `package.json`**
- 想提前装好（例如 CI 或离线环境），执行 `node <skill>/scripts/install-deps.mjs`，
  支持 `--check`（只检查，缺失时退出码 1）/ `--force`（重装）/ `--remove`（清理）
- 脚本已内置全部浏览器环境垫片（jsdom 缺 `devicePixelRatio` / `top` / `FontFace` / `document.fonts` 等）
- 输出打印 `✓ xxx.excalidraw → img/xxx.excalidraw.svg (NNN bytes, viewBox=...)`

### 第 5 步：嵌入文档

```markdown
![用法一：本地同机部署拓扑](./某主题/img/xxx.excalidraw.svg)
```

### 第 6 步：视觉验收（改图 / 复杂图必做）

静态校验挡不住**渲染层语义坑**（样条甩尾、遮罩失效、标签重叠），改完图必须看一眼产物：

1. SVG → PNG 用内置脚本（`@resvg/resvg-js` 预编译二进制，零系统依赖，首次运行自动安装）：

   ```bash
   node <skill>/scripts/svg2png.mjs 某主题/img/xxx.excalidraw.svg [--width <px>]
   ```

   产物为同目录 `xxx.excalidraw.png`，仅验收用，可随删
2. **PNG 中中文显示为方框 = 验收环境缺 CJK 字体**（脚本会检测并提示），
   SVG 本身正常——浏览器 / Excalidraw 打开即正确，不要因此返工改图
3. 验收看点：箭头两端是否贴框、折线无甩尾、标签遮罩下虚线不穿字、无重叠截断；
   逐项给出 pass/fail 证据，不通过就回源 JSON 修再重渲染，**禁止手改 SVG**

内置脚本不可用时的兜底（如老版本技能）：rsvg / inkscape / 无头浏览器，如
`firefox --headless --no-remote --profile /tmp/ffprof --screenshot out.png "file://...svg" --window-size=W,H`
（firefox 已有实例在跑时必须用 `--profile` 隔离 + `--no-remote`，否则直接退出码 2 失败）

## 已有场景的解析与修改

`.excalidraw` 是纯 JSON，直接用 `read_file` 读取即可理解结构。批量修改时：

1. 读取 JSON，按 `type` 过滤元素（节点是 `rectangle`、标题文字 `containerId` 为 null、箭头是 `arrow`）
2. 修改后写回，**保持元素顺序即层级**这一约定
3. 重新跑校验脚本确认引用没被写坏（改 id 时尤其注意 `boundElements` 与 `containerId`）

## 资源

### 脚本（scripts/）

- `install-deps.mjs` —— 安装渲染依赖到 `.render-runtime/`，支持 `--check` / `--force` / `--remove`
- `render-excalidraw.mjs` —— 场景 → SVG 渲染，含 DOM 垫片，依赖缺失时自动调用安装脚本
- `svg2png.mjs` —— SVG → PNG（视觉验收用，`@resvg/resvg-js` 预编译二进制、零系统依赖），
  支持 `--out-dir` / `--width` / `--zoom`；缺中文字体时提示「方框是环境问题而非 SVG 问题」
- `validate-scene.mjs` —— 零依赖结构校验，`--fix` 可自动补齐字段

### 参考（references/）

- `scene-format.md` —— 完整的元素字段表、文本/箭头绑定规则、字体与中文处理、
  布局估算方法、以及环境避坑清单（Kroki 不可用、主包 Node 导入失败等）

### 素材（assets/）

- `template-scene.excalidraw` —— 字段齐全的最小场景模板，作为手写起点
- `template-arrow-patterns.excalidraw` —— 箭头入射/绕行合法形态示例：
  扇形斜连（斜向成角进出）、直角折线绕行、三点甩弧绕行
- `template-flowchart.excalidraw` —— 流程图规范画法模板（双子图）：起止/执行/判断节点、
  是-否分支标签、回路折线、多框汇入同一框、汇集总线统一汇入

### 打包分发

没有专用打包脚本；整目录 zip / 拷贝分发前先清理渲染依赖：
`node scripts/install-deps.mjs --remove`（删除 `.render-runtime/`，约 100MB），目标机首次渲染会自动重装。
该目录已在 `.gitignore` 中，git 操作不会带上它。

## 注意事项

- **保留 `.excalidraw` 源文件**：SVG 是产物，改图要改源再重渲染；禁止手改 SVG
- **不要依赖 Kroki 在线渲染**：其实测 excalidraw 转换服务返回 HTTP 500（最小场景也失败）
- **注意产物命名冲突**：场景中常有同名 `.dot` 源文件，渲染前先确认 `img/` 下已有的 `.svg` 归属，
  本技能脚本已用 `<stem>.excalidraw.svg` 规避，自定义输出路径时不要手动改成 `<stem>.svg`
- **不要装 `@excalidraw/excalidraw` 主包做命令行渲染**：它的 bundle 裸导入 CSS，Node 会报
  `ERR_IMPORT_ATTRIBUTE_MISSING`；命令行场景一律用 `@excalidraw/utils`
- **与 graphviz-diagram 的分工**：需要「改源码自动重排」的图用 graphviz/plantuml；
  需要「交付给用户自己拖拽编辑」的图用 excalidraw
- 同一项目内固定用技能脚本渲染，避免不同环境（本地 graphviz 版本、在线服务）产生布局差异
