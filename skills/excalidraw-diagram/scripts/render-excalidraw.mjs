#!/usr/bin/env node
/**
 * 把 .excalidraw 场景渲染为 SVG。
 *
 * 用法:
 *   node render-excalidraw.mjs <scene.excalidraw> [...] [--out-dir <dir>]
 *
 * 输出:
 *   默认写到每个场景文件同级的 img/ 目录，文件名形如 <stem>.excalidraw.svg
 *   （保留 .excalidraw 标识，避免同名 .dot 渲染出的 <stem>.svg 被覆盖）
 *
 * 依赖:
 *   渲染依赖装在技能目录的 .render-runtime/ 下（不污染项目的 package.json）。
 *   首次渲染时会自动安装，也可提前手动执行: node install-deps.mjs
 */
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { RUNTIME_DIR, ensureDeps } from "./install-deps.mjs";

function parseArgs(argv) {
  const files = [];
  let outDir = null;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--out-dir") outDir = argv[++i];
    else files.push(argv[i]);
  }
  return { files, outDir };
}

/** 用 jsdom 补齐 excalidraw 运行所需的浏览器全局量 */
async function setupDomShim(JSDOM) {
  const dom = new JSDOM("<!DOCTYPE html><html><body></body></html>", {
    pretendToBeVisual: true,
    url: "http://localhost",
  });

  globalThis.window = dom.window;
  // Node 24 下 navigator 等是只读 getter，必须 defineProperty
  for (const k of Object.getOwnPropertyNames(dom.window)) {
    if (k in globalThis) continue;
    try {
      globalThis[k] = dom.window[k];
    } catch {}
  }
  for (const k of ["self", "top", "parent", "document", "navigator", "location"]) {
    try {
      Object.defineProperty(globalThis, k, {
        value: dom.window[k],
        configurable: true,
        writable: true,
      });
    } catch {}
  }
  globalThis.devicePixelRatio = 1;

  // jsdom 未实现 FontFace / document.fonts，需桩
  class FontFaceStub {
    constructor(family, source, descriptors = {}) {
      this.family = family;
      this.source = source;
      this.descriptors = descriptors;
      this.status = "loaded";
    }
    async load() {
      this.status = "loaded";
      return this;
    }
  }
  globalThis.FontFace = FontFaceStub;
  dom.window.FontFace = FontFaceStub;

  const fontSet = new Set();
  Object.defineProperty(dom.window.document, "fonts", {
    configurable: true,
    value: {
      add: (f) => fontSet.add(f),
      delete: (f) => fontSet.delete(f),
      clear: () => fontSet.clear(),
      check: () => true,
      load: async () => [],
      ready: Promise.resolve(),
      size: 0,
      forEach: () => {},
      entries: () => fontSet.values(),
      values: () => fontSet.values(),
      [Symbol.iterator]: () => fontSet.values(),
    },
  });
}

async function main() {
  const { files, outDir } = parseArgs(process.argv.slice(2));
  if (files.length === 0) {
    console.error("用法: node render-excalidraw.mjs <scene.excalidraw> [...] [--out-dir <dir>]");
    process.exit(1);
  }

  ensureDeps();

  const req = createRequire(path.join(RUNTIME_DIR, "noop.js"));
  const { JSDOM } = await import(pathToFileURL(req.resolve("jsdom")).href);
  await setupDomShim(JSDOM);
  const { exportToSvg } = await import(pathToFileURL(req.resolve("@excalidraw/utils")).href);

  // Excalidraw 内置的中文字体 Xiaolai 在无头环境下读不到 unicodeRange，
  // 生成 @font-face CSS 时会打印一条非致命错误（中文会回退系统字体，出图正常）。静音该噪声。
  const origError = console.error;
  console.error = (...args) => {
    if (typeof args[0] === "string" && args[0].includes("Couldn't transform font-face")) return;
    origError(...args);
  };

  let ok = 0;
  let fail = 0;

  for (const file of files) {
    const abs = path.resolve(file);
    if (!fs.existsSync(abs)) {
      console.error(`✗ ${file} 文件不存在`);
      fail++;
      continue;
    }
    try {
      const scene = JSON.parse(fs.readFileSync(abs, "utf8"));
      if (!Array.isArray(scene.elements) || scene.elements.length === 0) {
        console.error(`✗ ${file} 场景中没有元素`);
        fail++;
        continue;
      }

      const svg = await exportToSvg({
        elements: scene.elements,
        appState: {
          ...(scene.appState || {}),
          exportBackground: true,
          exportWithDarkMode: false,
          exportEmbedScene: false,
        },
        files: {},
      });

      const html = svg.outerHTML;
      const target = path.join(
        outDir ? path.resolve(outDir) : path.join(path.dirname(abs), "img"),
        `${path.basename(file, ".excalidraw")}.excalidraw.svg`,
      );
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, html);

      const vb = html.match(/viewBox="([^"]+)"/);
      console.log(
        `✓ ${path.basename(file)} → ${path.relative(process.cwd(), target)} ` +
          `(${html.length} bytes${vb ? `, viewBox=${vb[1]}` : ""})`,
      );
      ok++;
    } catch (err) {
      console.error(`✗ ${file} ${err.message}`);
      fail++;
    }
  }

  console.log(`\n完成: ${ok} 成功, ${fail} 失败`);
  if (fail > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
