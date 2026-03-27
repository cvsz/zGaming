import { readdir } from "node:fs/promises";
import path from "node:path";

export async function loadModules(directory: string): Promise<unknown[]> {
  const entries = await readdir(directory, { withFileTypes: true });
  const modules: unknown[] = [];

  for (const entry of entries) {
    if (!entry.isFile() || !entry.name.endsWith(".js")) {
      continue;
    }

    const modulePath = path.resolve(directory, entry.name);
    const mod = await import(modulePath);

    if (!mod.default) {
      throw new Error(`Invalid plugin module (missing default export): ${entry.name}`);
    }

    modules.push(mod.default);
  }

  return modules;
}
