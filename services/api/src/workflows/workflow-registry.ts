import type { WorkflowDefinition } from "./types.js";

export class WorkflowRegistry {
  private readonly definitions = new Map<string, WorkflowDefinition>();

  register(definition: WorkflowDefinition): void {
    if (this.definitions.has(definition.id)) {
      throw new Error(`Duplicate workflow id: ${definition.id}`);
    }
    if (definition.risk === "high" && definition.enabled) {
      throw new Error(`High-risk workflow cannot be enabled by default: ${definition.id}`);
    }
    this.definitions.set(definition.id, definition);
  }

  list(): WorkflowDefinition[] {
    return [...this.definitions.values()];
  }

  get(definitionId: string): WorkflowDefinition | undefined {
    return this.definitions.get(definitionId);
  }
}
