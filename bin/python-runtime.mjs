import { spawnSync } from "node:child_process";

const versionCheck =
  "import sys; raise SystemExit(sys.version_info < (3, 10))";

export function findPython(spawn = spawnSync) {
  for (const executable of ["python3", "python"]) {
    const result = spawn(executable, ["-c", versionCheck], {
      stdio: "ignore",
      windowsHide: true,
    });
    if (!result.error && result.status === 0) return executable;
  }
  return null;
}
