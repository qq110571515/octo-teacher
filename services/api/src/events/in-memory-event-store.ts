import type { EventFilter, EventStore, PlatformEvent } from "./types.js";

export class InMemoryEventStore implements EventStore {
  private readonly events: PlatformEvent[] = [];
  private readonly ids = new Set<string>();

  append(event: PlatformEvent): void {
    if (this.ids.has(event.id)) {
      throw new Error(`Duplicate event id: ${event.id}`);
    }
    this.ids.add(event.id);
    this.events.push(event);
  }

  appendMany(events: PlatformEvent[]): void {
    for (const event of events) {
      this.append(event);
    }
  }

  list(filter: EventFilter = {}): PlatformEvent[] {
    return this.events.filter((event) => {
      if (filter.familyId && event.familyId !== filter.familyId) return false;
      if (filter.childId && event.childId !== filter.childId) return false;
      if (filter.type && event.type !== filter.type) return false;
      if (filter.source && event.source !== filter.source) return false;
      if (filter.aggregateType && event.aggregate.type !== filter.aggregateType) return false;
      return true;
    });
  }
}
