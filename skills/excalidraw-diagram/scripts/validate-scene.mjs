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
 *   5. 质量警告（废弃字体、文本可能溢出容器）
 *
 * --fix: 自动补齐可安全推导的字段（index / originalText / autoResize），
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

  const elements = scene.elements || [];
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
