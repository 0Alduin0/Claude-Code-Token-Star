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

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const projectRoot = process.cwd();
const installRoot = join(projectRoot, ".claude-token-star");
const command = (process.argv[2] || "install").toLowerCase();
const forwardedArgs = process.argv.slice(3);
const packageJson = JSON.parse(
  readFileSync(join(packageRoot, "package.json"), "utf8"),
);

const runtimeFiles = [
  "VERSION",
  "claude-settings.example.json",
  "claude-settings.windows.example.json",
  "install.cmd",
  "install.ps1",
  "install.sh",
  "preview.html",
  "preview.ps1",
  "supernova.glsl",
  "supernova-windows.hlsl",
  "token-mass.py",
  "token-mass-windows.ps1",
  "token-star-overlay.ps1",
  "token-test.cmd",
  "token-test.ps1",
  "token-test.sh",
  "uninstall.cmd",
  "uninstall.ps1",
  "uninstall.sh",
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
  for (const name of runtimeFiles) {
    const source = join(packageRoot, name);
    if (!existsSync(source)) fail(`package is missing ${name}`);
    cpSync(source, join(installRoot, name), { force: true });
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

function showHelp() {
  console.log(`Claude Code Token Star ${packageJson.version}

Usage:
  claude-token-star [install]   Install or update the current project
  claude-token-star uninstall  Remove it from the current project
  claude-token-star doctor     Check the installation
  claude-token-star sweep      Preview every stellar stage
  claude-token-star off        Hide/reset the star
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
      ...forwardedArgs,
    ]);
  } else {
    run("sh", [join(installRoot, "install.sh"), ...forwardedArgs]);
  }
} else if (command === "uninstall") {
  if (process.platform === "win32") {
    runPowerShell(installedFile("uninstall.ps1"), forwardedArgs);
  } else {
    run("sh", [installedFile("uninstall.sh"), ...forwardedArgs]);
  }
  rmSync(installRoot, { recursive: true, force: true });
  console.log(`Removed ${installRoot}`);
} else if (["doctor", "sweep", "off"].includes(command)) {
  if (process.platform === "win32") {
    runPowerShell(installedFile("token-test.ps1"), [command, ...forwardedArgs]);
  } else {
    run("python3", [
      installedFile("token-mass.py"),
      `--${command}`,
      ...forwardedArgs,
    ]);
  }
} else {
  fail(`unknown command ${JSON.stringify(command)}; run with --help.`);
}
