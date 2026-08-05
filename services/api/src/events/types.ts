export type PlatformEvent = {
  id: string;
  type: string;
  schemaVersion: number;
  source: string;
  familyId: string;
  childId?: string;
  aggregate: {
    type: string;
    id: string;
    version?: number;
  };
  occurredAt: string;
  correlationId: string;
  causationId?: string;
  payload: Record<string, unknown>;
  metadata?: Record<string, string | number | boolean>;
};

export type EventFilter = {
  familyId?: string;
  childId?: string;
  type?: string;
  source?: string;
  aggregateType?: string;
};

export interface EventStore {
  append(event: PlatformEvent): void;
  appendMany(events: PlatformEvent[]): void;
  list(filter?: EventFilter): PlatformEvent[];
}
