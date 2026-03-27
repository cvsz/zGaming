import { EventEmitter } from "node:events";

export type RuntimeModule = {
  name: string;
  init(): Promise<void>;
  shutdown(): Promise<void>;
};

export class Kernel {
  private readonly modules = new Map<string, RuntimeModule>();
  private readonly bus = new EventEmitter();

  register(module: RuntimeModule): void {
    if (this.modules.has(module.name)) {
      throw new Error(`Duplicate module registration: ${module.name}`);
    }

    this.modules.set(module.name, module);
    this.bus.emit("module:registered", module.name);
  }

  async boot(): Promise<void> {
    for (const module of this.modules.values()) {
      try {
        await module.init();
        this.bus.emit("module:started", module.name);
      } catch (error) {
        this.bus.emit("module:error", module.name, error);
        throw error;
      }
    }
  }

  async shutdown(): Promise<void> {
    const startedModules = [...this.modules.values()].reverse();

    for (const module of startedModules) {
      await module.shutdown();
      this.bus.emit("module:stopped", module.name);
    }
  }

  getBus(): EventEmitter {
    return this.bus;
  }
}
