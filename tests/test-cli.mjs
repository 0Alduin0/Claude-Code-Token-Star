import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { findPython } from "../bin/python-runtime.mjs";

const packageJson = JSON.parse(readFileSync("package.json", "utf8"));
const fileVersion = readFileSync("VERSION", "utf8").trim();
const cli = "bin/claude-token-star.mjs";

assert.equal(packageJson.version, fileVersion, "VERSION must match package.json");

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

console.log("CLI contract OK");
