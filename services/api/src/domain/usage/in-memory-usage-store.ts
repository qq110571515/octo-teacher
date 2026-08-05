import type { AiUsageEvent, AppUsageEvent, UsageRollup } from "./types.js";

export class InMemoryUsageStore {
  private readonly aiEvents: AiUsageEvent[] = [];
  private readonly appEvents: AppUsageEvent[] = [];

  recordAiUsage(event: AiUsageEvent): void {
    if (event.inputTokens < 0 || event.outputTokens < 0 || event.costUsd < 0) {
      throw new Error("AI usage values must be non-negative.");
    }
    this.aiEvents.push(event);
  }

  recordAppUsage(event: AppUsageEvent): void {
    this.appEvents.push(event);
  }

  aiRollupByFamily(): UsageRollup[] {
    const rollups = new Map<string, UsageRollup>();
    for (const event of this.aiEvents) {
      const key = event.familyId ?? "unattributed";
      const rollup = rollups.get(key) ?? {
        familyId: event.familyId,
        totalInputTokens: 0,
        totalOutputTokens: 0,
        totalCostUsd: 0,
        eventCount: 0,
      };
      rollup.totalInputTokens += event.inputTokens;
      rollup.totalOutputTokens += event.outputTokens;
      rollup.totalCostUsd += event.costUsd;
      rollup.eventCount += 1;
      rollups.set(key, rollup);
    }
    return [...rollups.values()];
  }

  appEventCount(kind: AppUsageEvent["kind"]): number {
    return this.appEvents.filter((event) => event.kind === kind).length;
  }
}
