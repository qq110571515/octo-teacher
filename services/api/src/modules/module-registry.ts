import type { ModuleManifest, ModuleRegistryFinding } from "./types.js";

export class ModuleRegistry {
  private readonly manifests = new Map<string, ModuleManifest>();

  register(manifest: ModuleManifest): void {
    if (this.manifests.has(manifest.id)) {
      throw new Error(`Duplicate module id: ${manifest.id}`);
    }
    this.manifests.set(manifest.id, manifest);
  }

  list(): ModuleManifest[] {
    return [...this.manifests.values()];
  }

  get(moduleId: string): ModuleManifest | undefined {
    return this.manifests.get(moduleId);
  }

  audit(): ModuleRegistryFinding[] {
    const ids = new Set(this.manifests.keys());
    return this.list().flatMap((manifest) => {
      const findings: ModuleRegistryFinding[] = [];

      if (!manifest.owner.trim()) {
        findings.push({
          moduleId: manifest.id,
          severity: "block",
          code: "missing_owner",
          message: "Module must declare an owner.",
        });
      }

      if (manifest.docs.length === 0) {
        findings.push({
          moduleId: manifest.id,
          severity: "block",
          code: "missing_docs",
          message: "Module must link to docs before release.",
        });
      }

      if (manifest.capabilities.length === 0) {
        findings.push({
          moduleId: manifest.id,
          severity: "block",
          code: "missing_capability",
          message: "Module must declare runtime capabilities.",
        });
      }

      for (const dependency of manifest.dependencies) {
        if (!dependency.optional && !ids.has(dependency.moduleId)) {
          findings.push({
            moduleId: manifest.id,
            severity: "block",
            code: "missing_dependency",
            message: `Missing required dependency: ${dependency.moduleId}`,
          });
        }
      }

      for (const gate of manifest.releaseGates) {
        if (gate.required && gate.status === "missing") {
          findings.push({
            moduleId: manifest.id,
            severity: "block",
            code: "release_gate_missing",
            message: `Required release gate is missing: ${gate.id}`,
          });
        }
      }

      return findings;
    });
  }
}
