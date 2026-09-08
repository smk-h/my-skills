#!/usr/bin/env node
/**
 * 校验 .excalidraw 场景文件的结构完整性（零依赖，纯静态检查）。
 *
 * 用法:
 *   node validate-scene.mjs <scene.excalidraw> [...] [--fix]
 *
 * 检查项:
 *   1. JSON 可解析
 *   2. 各类型元素的必填字段（对照 excalidraw 0.18.1 官方类型定义）
 *   3. id 唯一性
 *   4. 引用有效性（containerId / boundElements / binding.elementId / frameId）
 *   5. 箭头几何（多拐点误配 roundness:2 会样条甩尾；端点未贴合绑定节点；首末段平行贴边）
 *   6. 节点框重叠：框与框不得部分交叠（压角/压边），容器/分组完全包含除外
 *   7. 质量警告（废弃字体、文本可能溢出容器）
 *
 * isDeleted: true 的墓碑元素（编辑器删除后留在 JSON 里的残影）不参与一切检查，
 * 否则编辑器保存的文件会报出一堆已删除元素的假穿框/假引用。
 *
 * --fix: 自动补齐可安全推导的字段（index / originalText / autoResize /
 *        linear 元素的 lastCommittedPoint / binding 的 focus 与 gap），
 *        并把废弃的 fontFamily 1（Virgil）改为 5（Excalifont）
 */
import fs from "node:fs";
import path from "node:path";

const BASE = [
  "id", "x", "y", "width", "height", "angle", "strokeColor", "backgroundColor",
  "fillStyle", "strokeWidth", "strokeStyle", "roundness", "roughness", "opacity",
  "seed", "version", "versionNonce", "index", "isDeleted", "groupIds", "frameId",
  "boundElements", "updated", "link", "locked",
];

const EXTRA = {
  text: ["fontSize", "fontFamily", "text", "textAlign", "verticalAlign", "containerId", "originalText", "autoResize", "lineHeight"],
  arrow: ["points", "lastCommittedPoint", "startBinding", "endBinding", "startArrowhead", "endArrowhead", "elbowed"],
  line: ["points", "lastCommittedPoint", "startBinding", "endBinding", "startArrowhead", "endArrowhead"],
  freedraw: ["points", "pressures", "simulatePressure", "lastCommittedPoint"],
  image: ["fileId", "status", "scale", "naturalWidth", "naturalHeight"],
  frame: ["name"],
};

const args = process.argv.slice(2);
const fix = args.includes("--fix");
const files = args.filter((a) => a !== "--fix");

if (files.length === 0) {
  console.error("用法: node validate-scene.mjs <scene.excalidraw> [...] [--fix]");
  process.exit(1);
}

let totalErrors = 0;

for (const file of files) {
  const abs = path.resolve(file);
  let scene;
  try {
    scene = JSON.parse(fs.readFileSync(abs, "utf8"));
  } catch (err) {
    console.error(`✗ ${file} JSON 解析失败: ${err.message}`);
    totalErrors++;
    continue;
  }

  const elements = (scene.elements || []).filter((e) => e.isDeleted !== true);
  const errors = [];
  const warnings = [];
  const ids = new Set();

  if (fix) {
    for (const el of elements) {
      if (el.index === undefined) el.index = null;
      if (el.type === "text") {
        if (el.originalText === undefined) el.originalText = el.text;
        if (el.autoResize === undefined) el.autoResize = true;
        if (el.fontFamily === 1) el.fontFamily = 5;
      }
      if (el.type === "arrow" || el.type === "line" || el.type === "freedraw") {
        if (el.lastCommittedPoint === undefined) el.lastCommittedPoint = null;
      }
      for (const key of ["startBinding", "endBinding"]) {
        const b = el[key];
        if (b && b.elementId) {
          if (b.focus === undefined) b.focus = 0;
          if (b.gap === undefined) b.gap = 4;
        }
      }
    }
  }

  for (const el of elements) {
    if (ids.has(el.id)) errors.push(`重复 id: ${el.id}`);
    ids.add(el.id);

    const required = [...BASE, ...(EXTRA[el.type] || [])];
    if (!EXTRA[el.type] && !["rectangle", "diamond", "ellipse", "embeddable", "iframe", "selection", "magicframe"].includes(el.type)) {
      warnings.push(`${el.id} 未知元素类型 "${el.type}"，跳过字段检查`);
    }
    for (const k of required) {
      if (!(k in el)) errors.push(`${el.id} 缺少必填字段 ${k}`);
    }

    if (el.type === "text") {
      if (el.fontFamily === 1) warnings.push(`${el.id} 使用废弃字体 fontFamily=1 (Virgil)，建议改为 5 (Excalifont)`);
    }
    if (el.type === "arrow" && !Array.isArray(el.points)) errors.push(`${el.id} points 必须是数组`);
  }

  // 引用完整性
  for (const el of elements) {
    if (el.containerId && !ids.has(el.containerId)) errors.push(`${el.id}.containerId → ${el.containerId} 不存在`);
    for (const b of el.boundElements || []) {
      if (!ids.has(b.id)) errors.push(`${el.id}.boundElements → ${b.id} 不存在`);
    }
    for (const key of ["startBinding", "endBinding"]) {
      if (el[key] && el[key].elementId && !ids.has(el[key].elementId)) {
        errors.push(`${el.id}.${key}.elementId → ${el[key].elementId} 不存在`);
      }
    }
    if (el.frameId && !ids.has(el.frameId)) errors.push(`${el.id}.frameId → ${el.frameId} 不存在`);
  }

  // 文本溢出粗检：CJK 按 1em、拉丁按 0.6em 估算
  // 仅对矩形/菱形/椭圆这类「真容器」检查；箭头是线性元素，其 width 是包围盒，不适用
  const TEXT_CONTAINERS = ["rectangle", "diamond", "ellipse"];
  const byId = new Map(elements.map((e) => [e.id, e]));
  for (const el of elements) {
    if (el.type !== "text" || !el.containerId) continue;
    const c = byId.get(el.containerId);
    if (!c || !TEXT_CONTAINERS.includes(c.type)) continue;
    const lines = String(el.text).split("\n");
    const widest = Math.max(
      ...lines.map((line) =>
        [...line].reduce(
          (w, ch) => w + (/[\u4e00-\u9fff\uff00-\uffef]/.test(ch) ? 1 : 0.6) * el.fontSize,
          0,
        ),
      ),
    );
    if (widest > c.width * 0.95) {
      warnings.push(
        `${el.id} 文本估算宽度 ${Math.round(widest)}px 接近/超出容器 ${c.id} 宽度 ${c.width}px，可能溢出`,
      );
    }
  }

  // 节点框重叠检查：框与框不得部分交叠（互相压角/压边），那必然是坐标错位；
  // 唯一合法的交叠是「完全包含」——容器/分组框与组内节点。相邻贴边（交叠深度
  // ≤ EPS，含坐标抖动）不算重叠。NODE_TYPES: 有实体包围盒、可被箭头吸附的节点元素
  const NODE_TYPES = ["rectangle", "diamond", "ellipse"];
  const nodes = elements.filter((e) => NODE_TYPES.includes(e.type));
  const OVERLAP_EPS = 2;      // 交叠深度 ≤2px 视为贴边/抖动，不算重叠
  const CONTAIN_SLACK = 2;    // 包含判定容差：组内节点相对外框准出 ≤2px 仍视为在框内
  const boxContains = (outer, inner) =>
    outer.x - CONTAIN_SLACK <= inner.x && outer.y - CONTAIN_SLACK <= inner.y &&
    outer.x + outer.width + CONTAIN_SLACK >= inner.x + inner.width &&
    outer.y + outer.height + CONTAIN_SLACK >= inner.y + inner.height;
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      const dw = Math.min(nodes[i].x + nodes[i].width, nodes[j].x + nodes[j].width) - Math.max(nodes[i].x, nodes[j].x);
      const dh = Math.min(nodes[i].y + nodes[i].height, nodes[j].y + nodes[j].height) - Math.max(nodes[i].y, nodes[j].y);
      if (dw <= OVERLAP_EPS || dh <= OVERLAP_EPS) continue;
      if (boxContains(nodes[i], nodes[j]) || boxContains(nodes[j], nodes[i])) continue;
      errors.push(
        `${nodes[i].id} 与 ${nodes[j].id} 框体部分交叠（重叠 ${Math.round(dw)}×${Math.round(dh)}px）：框不得互相重叠，错开坐标或改成容器包含关系`,
      );
    }
  }

  // 箭头几何检查（line/arrow 同规则）：
  //   检查 1 线体穿框；检查 2 转角甩尾分类；检查 3 端点贴合；检查 4 入射方向禁平行
  // 线段与矩形相交（Liang-Barsky 裁剪判定）：矩形取自 (rx1,ry1)-(rx2,ry2)
  const segmentIntersectsRect = (x1, y1, x2, y2, rx1, ry1, rx2, ry2) => {
    const dx = x2 - x1, dy = y2 - y1;
    let t0 = 0, t1 = 1;
    const clip = (p, q) => {
      if (p === 0) return q >= 0;
      const r = q / p;
      if (p < 0) { if (r > t1) return false; if (r > t0) t0 = r; }
      else { if (r < t0) return false; if (r < t1) t1 = r; }
      return true;
    };
    return clip(-dx, x1 - rx1) && clip(dx, rx2 - x1) &&
           clip(-dy, y1 - ry1) && clip(dy, ry2 - y1);
  };
  // 判断一个绝对坐标点是否贴合某节点的边框：在包围盒扩展 ±tolerance 的环带内、
  // 但不在收缩 -tolerance 的内核内（后者视为「扎进框内」）
  const onBorder = (node, px, py, tolerance) =>
    px >= node.x - tolerance && px <= node.x + node.width + tolerance &&
    py >= node.y - tolerance && py <= node.y + node.height + tolerance &&
    !(px > node.x + tolerance && px < node.x + node.width - tolerance &&
      py > node.y + tolerance && py < node.y + node.height - tolerance);
  for (const el of elements) {
    if (el.type !== "arrow" && el.type !== "line") continue;
    if (!Array.isArray(el.points) || el.points.length === 0) continue;

    // 检查 1：箭头线体不得穿框（线段-矩形相交，Liang-Barsky）。
    // 豁免：起/终点绑定的节点自身；以及包含起/终点节点的祖先容器
    //（箭头进组/出组必然穿过组容器边框，属合法语义）。
    // 样条箭头（roundness type 2 且 ≥3 点）的实际曲线与折线弦不同，按弦近似检查、降级为警告。
    const TOLERANCE = 6;
    const contains = (outer, inner) =>
      outer.x <= inner.x && outer.y <= inner.y &&
      outer.x + outer.width >= inner.x + inner.width &&
      outer.y + outer.height >= inner.y + inner.height;
    const sNode = el.startBinding && byId.get(el.startBinding.elementId);
    const eNode = el.endBinding && byId.get(el.endBinding.elementId);
    const exemptCross = (n) =>
      n === sNode || n === eNode ||
      (sNode && NODE_TYPES.includes(n.type) && contains(n, sNode)) ||
      (eNode && NODE_TYPES.includes(n.type) && contains(n, eNode));
    const isSpline = el.roundness && el.roundness.type === 2 && el.points.length >= 3;
    for (const n of nodes) {
      if (exemptCross(n)) continue;
      for (let i = 1; i < el.points.length; i++) {
        const [x1, y1] = el.points[i - 1], [x2, y2] = el.points[i];
        if (segmentIntersectsRect(
          el.x + x1, el.y + y1, el.x + x2, el.y + y2,
          n.x + TOLERANCE, n.y + TOLERANCE,
          n.x + n.width - TOLERANCE, n.y + n.height - TOLERANCE,
        )) {
          const msg = `${el.id} 线体穿过节点 ${n.id}，箭头不得从框上过；用弧线箭头（多点小转角）或折线箭头（roundness:null）绕行` +
            (isSpline ? `（样条按折线弦近似检查）` : ``);
          (isSpline ? warnings : errors).push(msg);
          break; // 每个节点只报一次
        }
      }
    }

    // 检查 2：转角分类。多拐点配 roundness:{type:2} 不再一概而论——
    //   每段转角 ≤ ~35°：type 2 样条就是平滑弧线，合法（实测 9 点 22.5° 弧线偏移仅 ±2px）
    //   三点甩弧（共 3 点、单个拐角）> ~50°：编辑器原生弧线箭头画法，曲线向拐角内侧
    //   自然收弯（实测 77° 内偏约 50px），只要拐点离被绕框留足余量就是干净的绕行弧，
    //   降为警告提醒视觉验收
    //   ≥4 点且任意转角 > ~50°：type 2 会在拐角拉出大幅弧线甩尾（实测 90° 甩 74px、45° 甩 57px），
    //   必须 roundness:null 直角折线
    //   两者之间（35°-50°）视为风险区，给出警告
    if (el.points.length > 2) {
      let maxTurn = 0;
      for (let i = 1; i < el.points.length - 1; i++) {
        const [ax, ay] = el.points[i - 1], [bx, by] = el.points[i], [cx, cy] = el.points[i + 1];
        const v1 = [bx - ax, by - ay], v2 = [cx - bx, cy - by];
        const d1 = Math.hypot(...v1), d2 = Math.hypot(...v2);
        if (d1 === 0 || d2 === 0) continue;
        maxTurn = Math.max(maxTurn, Math.acos(Math.min(1, Math.max(-1, (v1[0]*v2[0]+v1[1]*v2[1]) / (d1*d2)))) * 180 / Math.PI);
      }
      if (el.roundness && el.roundness.type === 2) {
        if (maxTurn > 50 && el.points.length === 3) warnings.push(
          `${el.id} 三点甩弧拐角 ${maxTurn.toFixed(0)}° 配 roundness:{type:2}：曲线向拐角内侧偏移（实测 77° 内偏约 50px），确认拐点离被绕框留足余量，以渲染产物视觉验收为准`,
        );
        else if (maxTurn > 50) errors.push(
          `${el.id} 存在 ${maxTurn.toFixed(0)}° 拐角且配 roundness:{type:2}，样条会在此甩尾（90° 实测甩 74px），直角/大拐角路由必须 roundness:null`,
        );
        else if (maxTurn > 35) warnings.push(
          `${el.id} 拐角 ${maxTurn.toFixed(0)}° 配 roundness:{type:2} 处于样条甩尾风险区（35°-50°），建议改 roundness:null 或把拐角放缓到 ≤35°`,
        );
      }
    }

    // 检查 3：端点贴合。首尾端点必须贴合某个节点的边框，否则箭头指向不明。
    // 合法形态（按优先级）：
    //   a. 贴 binding 指向节点自身的边框
    //   b. 贴其他任意节点的边框 —— 「组内节点出组」画法（箭头从外层容器边框引出）
    //   c. 位于包含 binding 节点的祖先容器内部 —— 同为「出组」语义
    // 违规形态：扎进某节点内部 / 悬在空白处。
    const insideCore = (node, px, py) =>
      px > node.x + TOLERANCE && px < node.x + node.width - TOLERANCE &&
      py > node.y + TOLERANCE && py < node.y + node.height - TOLERANCE;
    const ends = [
      ["startBinding", el.points[0]],
      ["endBinding", el.points[el.points.length - 1]],
    ];
    for (const [key, pt] of ends) {
      const b = el[key];
      if (!b || !b.elementId) continue;
      const node = byId.get(b.elementId);
      if (!node || !NODE_TYPES.includes(node.type)) continue;
      const px = el.x + pt[0];
      const py = el.y + pt[1];
      const anchored = nodes.some((n) => onBorder(n, px, py, TOLERANCE));
      if (!anchored) {
        if (insideCore(node, px, py)) {
          errors.push(
            `${el.id} ${key} 端点 (${px},${py}) 扎进节点 ${node.id} 内部，应贴到边框上`,
          );
        } else {
          const buried = nodes.find((n) => n !== node && insideCore(n, px, py) && !contains(n, node));
          if (buried) {
            errors.push(
              `${el.id} ${key} 端点 (${px},${py}) 扎进无关节点 ${buried.id} 内部，应贴到 ${node.id} 边框上`,
            );
          } else {
            errors.push(
              `${el.id} ${key} 端点 (${px},${py}) 悬空（距节点 ${node.id} 边框 > ${TOLERANCE}px），箭头指向不明`,
            );
          }
        }
      }
      // 检查 4：入射方向禁平行（不要求正交）。端点所在的首/末段线不能与贴合的框边
      // 平行——水平线落在左/右边框、垂直线落在顶/底边框时，线体贴着框边滑行，不美观。
      // 斜向成角进出完全合法（与边框有任何非零夹角即可，正交只是特例），
      // 故仅拦首/末段恰为水平/垂直且与所贴边共线的情形。样条末段方向取与端点相切
      // 的趋势，近似用首/末段弦向量判定。
      const adjacent = key === "startBinding" ? el.points[1] : el.points[el.points.length - 2];
      if (!adjacent) continue;
      const ax = el.x + adjacent[0], ay = el.y + adjacent[1];
      const horizontalLine = Math.abs(py - ay) < 2;   // 首末段是水平线
      const verticalLine = Math.abs(px - ax) < 2;     // 首末段是垂直线
      if (!horizontalLine && !verticalLine) continue;  // 斜向成角进出，合法
      const onTopOrBottom =
        Math.abs(py - node.y) <= TOLERANCE || Math.abs(py - (node.y + node.height)) <= TOLERANCE;
      const onLeftOrRight =
        Math.abs(px - node.x) <= TOLERANCE || Math.abs(px - (node.x + node.width)) <= TOLERANCE;
      if ((onTopOrBottom && horizontalLine) || (onLeftOrRight && verticalLine)) {
        errors.push(
          `${el.id} ${key} 首末段与贴合的 ${node.id} 边框平行（贴边滑行不美观）：换到面向目标的那条边，或让线与边框成角斜向进出（垂直/水平/斜向均可，禁止平行）`,
        );
      }
    }
  }

  if (fix) fs.writeFileSync(abs, JSON.stringify(scene, null, 2) + "\n");

  const counts = {};
  for (const el of elements) counts[el.type] = (counts[el.type] || 0) + 1;

  console.log(`\n${path.basename(file)}: ${elements.length} 个元素 ${JSON.stringify(counts)}`);
  if (errors.length) {
    totalErrors += errors.length;
    console.log(`  错误 ${errors.length}:`);
    for (const e of errors) console.log(`    - ${e}`);
  } else {
    console.log("  ✓ 结构与引用检查通过");
  }
  if (warnings.length) {
    console.log(`  警告 ${warnings.length}:`);
    for (const w of warnings) console.log(`    - ${w}`);
  }
  if (fix) console.log(`  --fix 已写回: ${path.basename(file)}`);
}

console.log(`\n合计错误: ${totalErrors}`);
if (totalErrors > 0) process.exit(1);
