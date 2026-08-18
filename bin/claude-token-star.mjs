#!/usr/bin/env node

import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { findPython } from "./python-runtime.mjs";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const projectRoot = process.cwd();
const installRoot = join(projectRoot, ".claude-token-star");
const projectClaudeSettings = join(
  projectRoot,
  ".claude",
  "settings.local.json",
);
const command = (process.argv[2] || "install").toLowerCase();
const forwardedArgs = process.argv.slice(3);
const packageJson = JSON.parse(
  readFileSync(join(packageRoot, "package.json"), "utf8"),
);

const runtimeFiles = [
  { source: "VERSION", destination: "VERSION" },
  ...(process.platform === "win32"
    ? [
        { source: "src/windows/install.ps1", destination: "install.ps1" },
        { source: "src/windows/uninstall.ps1", destination: "uninstall.ps1" },
        { source: "src/windows/token-mass-windows.ps1", destination: "token-mass-windows.ps1" },
        { source: "src/windows/token-star-overlay.ps1", destination: "token-star-overlay.ps1" },
        { source: "src/windows/supernova-windows.hlsl", destination: "supernova-windows.hlsl" },
        { source: "tools/token-test.ps1", destination: "token-test.ps1" },
        { source: "tools/preview.ps1", destination: "preview.ps1" },
        { source: "tools/preview.html", destination: "preview.html" },
        { source: "src/ghostty/supernova.glsl", destination: "supernova.glsl" },
      ]
    : [
        { source: "src/ghostty/install.sh", destination: "install.sh" },
        { source: "src/ghostty/uninstall.sh", destination: "uninstall.sh" },
        { source: "src/ghostty/token-mass.py", destination: "token-mass.py" },
        { source: "src/ghostty/token-test.sh", destination: "token-test.sh" },
        { source: "src/ghostty/supernova.glsl", destination: "supernova.glsl" },
      ]),
];

function fail(message) {
  console.error(`claude-token-star: ${message}`);
  process.exit(1);
}

function run(executable, args, cwd = projectRoot) {
  const result = spawnSync(executable, args, {
    cwd,
    stdio: "inherit",
    windowsHide: true,
  });
  if (result.error) fail(result.error.message);
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function isManagedInstall(path) {
  if (!existsSync(path)) return true;
  const versionPath = join(path, "VERSION");
  const installer = join(
    path,
    process.platform === "win32" ? "install.ps1" : "install.sh",
  );
  return existsSync(versionPath) && existsSync(installer);
}

function stageRuntime() {
  if (!isManagedInstall(installRoot)) {
    fail(`${installRoot} exists but is not a Claude Code Token Star install.`);
  }
  mkdirSync(installRoot, { recursive: true });
  for (const file of runtimeFiles) {
    const source = join(packageRoot, file.source);
    if (!existsSync(source)) fail(`package is missing ${file.source}`);
    cpSync(source, join(installRoot, file.destination), { force: true });
  }
}

function installedFile(name) {
  const path = join(installRoot, name);
  if (!existsSync(path)) {
    fail(`no local install found; run npx claude-token-star first.`);
  }
  return path;
}

function runPowerShell(script, args = []) {
  run("powershell.exe", [
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    script,
    ...args,
  ]);
}

function runPython(args) {
  const python = findPython();
  if (!python) fail("Python 3.10+ was not found on PATH.");
  run(python, args);
}

function showHelp() {
  console.log(`Claude Code Token Star ${packageJson.version}

Usage:
  claude-token-star [install]   Install or update the current project
  claude-token-star uninstall  Remove it from the current project
  claude-token-star doctor     Check the installation
  claude-token-star sweep      Preview every stellar stage
  claude-token-star on         Enable and start the Windows overlay
  claude-token-star off        Stop and disable the Windows overlay
  claude-token-star --version  Print the package version

Run the command from your project root. Windows supports the IDE overlay;
Linux and macOS currently require Ghostty.`);
}

if (["-h", "--help", "help"].includes(command)) {
  showHelp();
} else if (["-v", "--version", "version"].includes(command)) {
  console.log(packageJson.version);
} else if (command === "install") {
  stageRuntime();
  if (process.platform === "win32") {
    runPowerShell(join(installRoot, "install.ps1"), [
      "-ProjectPath",
      projectRoot,
      "-ClaudeSettings",
      projectClaudeSettings,
      ...forwardedArgs,
    ]);
  } else {
    run("sh", [join(installRoot, "install.sh"), ...forwardedArgs]);
  }
} else if (command === "uninstall") {
  if (process.platform === "win32") {
    runPowerShell(installedFile("uninstall.ps1"), [
      "-ProjectPath",
      projectRoot,
      "-ClaudeSettings",
      projectClaudeSettings,
      ...forwardedArgs,
    ]);
  } else {
    run("sh", [installedFile("uninstall.sh"), ...forwardedArgs]);
  }
  rmSync(installRoot, { recursive: true, force: true });
  console.log(`Removed ${installRoot}`);
} else if (["doctor", "sweep", "on", "off"].includes(command)) {
  if (process.platform === "win32") {
    runPowerShell(installedFile("token-test.ps1"), [
      command,
      "-ClaudeSettings",
      projectClaudeSettings,
      ...forwardedArgs,
    ]);
  } else {
    if (command === "on") {
      fail("the on command is only needed for the Windows IDE overlay.");
    }
    runPython([
      installedFile("token-mass.py"),
      `--${command}`,
      ...forwardedArgs,
    ]);
  }
} else {
  fail(`unknown command ${JSON.stringify(command)}; run with --help.`);
}
