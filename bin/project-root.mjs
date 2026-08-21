import { existsSync } from "node:fs";
import { basename, join, resolve } from "node:path";

export function resolveProjectRoot(cwd, platform = process.platform) {
  const invocationRoot = resolve(cwd);
  if (basename(invocationRoot).toLowerCase() !== ".claude-token-star") {
    return invocationRoot;
  }

  const installer = platform === "win32" ? "install.ps1" : "install.sh";
  const isManagedInstall =
    existsSync(join(invocationRoot, "VERSION")) &&
    existsSync(join(invocationRoot, installer));

  return isManagedInstall ? resolve(invocationRoot, "..") : invocationRoot;
}
