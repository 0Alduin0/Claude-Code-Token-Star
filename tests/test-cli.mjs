import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const packageJson = JSON.parse(readFileSync("package.json", "utf8"));
const fileVersion = readFileSync("VERSION", "utf8").trim();
const cli = "bin/claude-token-star.mjs";

assert.equal(packageJson.version, fileVersion, "VERSION must match package.json");

const help = spawnSync(process.execPath, [cli, "--help"], { encoding: "utf8" });
assert.equal(help.status, 0, help.stderr);
assert.match(help.stdout, /Install or update the current project/);
assert.match(help.stdout, /Linux and macOS currently require Ghostty/);

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

console.log("CLI contract OK");
