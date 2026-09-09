#!/usr/bin/env node
/**
 * 把 SVG 渲染为 PNG，供「视觉验收」环节看图用。
 *
 * 用法:
 *   node svg2png.mjs <file.svg> [...] [--out-dir <dir>] [--width <px>] [--zoom <n>]
 *
 * 输出:
 *   默认写到每个 SVG 同目录，文件名 <stem>.png
 *   （xxx.excalidraw.svg → xxx.excalidraw.png，仅验收用，可随时删除）
 *   --width 指定输出像素宽度（默认按 SVG 原始尺寸）
 *   --zoom  指定缩放倍数（与 --width 互斥）
 *
 * 依赖:
 *   @resvg/resvg-js（预编译二进制，不需要 libcairo 等系统库），
 *   装在技能目录的 .render-runtime/ 下，首次运行自动安装。
 *
 * 注意:
 *   验收环境缺中文字体时，PNG 里中文会显示为方框——这是环境问题，
 *   SVG 本身在浏览器 / Excalidraw 中显示正常，不要因此返工改图。
 *   检测到这种情况时脚本会在输出末尾打印提示。
 */
import { execSync } from "node:child_process";
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { RUNTIME_DIR, ensureDeps } from "./install-deps.mjs";

function parseArgs(argv) {
  const files = [];
  let outDir = null;
  let width = null;
  let zoom = null;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--out-dir") outDir = argv[++i];
    else if (argv[i] === "--width") width = Number(argv[++i]);
    else if (argv[i] === "--zoom") zoom = Number(argv[++i]);
    else files.push(argv[i]);
  }
  return { files, outDir, width, zoom };
}

/** 系统是否有中文字体（无 fontconfig 时视为无法判定，返回 null） */
function hasCjkFont() {
  try {
    const out = execSync("fc-list :lang=zh", { stdio: ["ignore", "pipe", "ignore"] })
      .toString()
      .trim();
    return out.length > 0;
  } catch {
    return null;
  }
}

async function main() {
  const { files, outDir, width, zoom } = parseArgs(process.argv.slice(2));
  if (files.length === 0) {
    console.error("用法: node svg2png.mjs <file.svg> [...] [--out-dir <dir>] [--width <px>] [--zoom <n>]");
    process.exit(1);
  }
  if (width && zoom) {
    console.error("--width 与 --zoom 互斥，只能指定一个");
    process.exit(1);
  }

  ensureDeps();

  const req = createRequire(path.join(RUNTIME_DIR, "noop.js"));
  const { Resvg } = req("@resvg/resvg-js");

  let ok = 0;
  let fail = 0;
  let sawCjk = false;

  for (const file of files) {
    const abs = path.resolve(file);
    if (!fs.existsSync(abs)) {
      console.error(`✗ ${file} 文件不存在`);
      fail++;
      continue;
    }
    try {
      const svg = fs.readFileSync(abs, "utf8");
      if (/[\u4e00-\u9fff]/.test(svg)) sawCjk = true;

      const fitTo = width
        ? { mode: "width", value: width }
        : zoom
          ? { mode: "zoom", value: zoom }
          : { mode: "original" };
      const png = new Resvg(svg, {
        fitTo,
        font: { loadSystemFonts: true },
      })
        .render()
        .asPng();

      const stem = path.basename(abs).replace(/\.svg$/i, "");
      const target = path.join(outDir ? path.resolve(outDir) : path.dirname(abs), `${stem}.png`);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, png);
      console.log(`✓ ${path.basename(file)} → ${path.relative(process.cwd(), target)} (${png.length} bytes)`);
      ok++;
    } catch (err) {
      console.error(`✗ ${file} ${err.message}`);
      fail++;
    }
  }

  if (sawCjk && hasCjkFont() !== true) {
    console.log("提示：未能确认系统装有中文字体；若 PNG 中中文显示为方框，");
    console.log("      是验收环境的字体问题，SVG 在浏览器 / Excalidraw 中显示正常，无需改图。");
  }

  console.log(`\n完成: ${ok} 成功, ${fail} 失败`);
  if (fail > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
