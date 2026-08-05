export type AuditRecord = {
  id: string;
  occurredAt: string;
  actorId: string;
  actorRole: string;
  action: string;
  resource: string;
  decision: "allowed" | "denied" | "recorded";
  reasonCode: string;
  correlationId: string;
  metadata?: Record<string, string | number | boolean>;
};

export interface AuditLog {
  append(record: AuditRecord): void;
  list(): AuditRecord[];
}
