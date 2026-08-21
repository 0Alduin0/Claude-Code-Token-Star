import assert from "node:assert/strict";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { findPython } from "../bin/python-runtime.mjs";
import { resolveProjectRoot } from "../bin/project-root.mjs";

const packageJson = JSON.parse(readFileSync("package.json", "utf8"));
const fileVersion = readFileSync("VERSION", "utf8").trim();
const cli = "bin/claude-token-star.mjs";
const cliSource = readFileSync(cli, "utf8");
const previewHtml = readFileSync("tools/preview.html", "utf8");
const previewRenderer = readFileSync("tools/preview-renderer.js", "utf8");

assert.equal(packageJson.version, fileVersion, "VERSION must match package.json");
assert.ok(packageJson.files.includes("tools/preview-renderer.js"), "preview renderer missing from package");
assert.match(cliSource, /preview-renderer\.js/, "preview renderer missing from staged runtime");
assert.match(previewHtml, /src="\.\/preview-renderer\.js"/, "browser preview does not load the current renderer");
assert.match(previewHtml, /id="preview-surface"/, "browser preview animation surface is missing");
assert.match(previewRenderer, /surface\.append\(stage\.image\)/, "WPF animations are not mounted as live image layers");
for (const slug of ["red-dwarf", "main-sequence", "blue-giant", "hypergiant", "neutron-star", "quasar"]) {
  const assetPath = `assets/preview/overlay-${slug}.webp`;
  assert.ok(existsSync(assetPath), `WPF preview asset missing for ${slug}`);
  const asset = readFileSync(assetPath);
  assert.equal(asset.subarray(0, 4).toString("ascii"), "RIFF", `invalid WebP container for ${slug}`);
  assert.ok(asset.includes(Buffer.from("ANIM")), `WPF preview asset is not animated for ${slug}`);
  assert.equal(asset.toString("latin1").match(/ANMF/g)?.length, 16, `WPF preview frame count changed for ${slug}`);
  assert.match(cliSource, new RegExp(`preview-${slug}\\.webp`), `WPF preview asset is not staged for ${slug}`);
}

const help = spawnSync(process.execPath, [cli, "--help"], { encoding: "utf8" });
assert.equal(help.status, 0, help.stderr);
assert.match(help.stdout, /Install or update the current project/);
assert.match(help.stdout, /Linux and macOS currently require Ghostty/);
assert.match(help.stdout, /on\s+Enable and start the Windows overlay/);
assert.match(help.stdout, /off\s+Stop and disable the Windows overlay/);

const version = spawnSync(process.execPath, [cli, "--version"], {
  encoding: "utf8",
});
assert.equal(version.status, 0, version.stderr);
assert.equal(version.stdout.trim(), packageJson.version);

const unknown = spawnSync(process.execPath, [cli, "nope"], {
  encoding: "utf8",
});
assert.equal(unknown.status, 1);
assert.match(unknown.stderr, /unknown command/);

const pythonCalls = [];
const python = findPython((executable, args) => {
  pythonCalls.push([executable, args]);
  return executable === "python"
    ? { error: undefined, status: 0 }
    : { error: new Error("not found"), status: null };
});
assert.equal(python, "python", "Python discovery must fall back to python");
assert.deepEqual(
  pythonCalls.map(([executable]) => executable),
  ["python3", "python"],
  "Python discovery order changed",
);
assert.match(pythonCalls[0][1][1], /3, 10/, "Python 3.10+ check missing");

const rootTest = mkdtempSync(join(tmpdir(), "claude-token-star-root-"));
try {
  const hiddenInstall = join(rootTest, ".claude-token-star");
  mkdirSync(hiddenInstall);
  writeFileSync(join(hiddenInstall, "VERSION"), "test\n");
  writeFileSync(join(hiddenInstall, "install.ps1"), "# test\n");
  assert.equal(
    resolveProjectRoot(hiddenInstall, "win32"),
    resolve(rootTest),
    "commands run inside the managed Windows install must target its parent project",
  );
  assert.equal(
    resolveProjectRoot(hiddenInstall, "linux"),
    resolve(hiddenInstall),
    "an incomplete install must not be mistaken for the current platform's managed install",
  );
  writeFileSync(join(hiddenInstall, "install.sh"), "# test\n");
  assert.equal(
    resolveProjectRoot(hiddenInstall, "linux"),
    resolve(rootTest),
    "commands run inside the managed Unix install must target its parent project",
  );
} finally {
  rmSync(rootTest, { recursive: true, force: true });
}

console.log("CLI contract OK");
