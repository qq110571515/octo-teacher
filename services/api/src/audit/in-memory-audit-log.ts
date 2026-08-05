import type { AuditLog, AuditRecord } from "./types.js";

export class InMemoryAuditLog implements AuditLog {
  private readonly records: AuditRecord[] = [];
  private readonly ids = new Set<string>();

  append(record: AuditRecord): void {
    if (this.ids.has(record.id)) {
      throw new Error(`Duplicate audit record id: ${record.id}`);
    }
    this.ids.add(record.id);
    this.records.push(record);
  }

  list(): AuditRecord[] {
    return [...this.records];
  }
}
