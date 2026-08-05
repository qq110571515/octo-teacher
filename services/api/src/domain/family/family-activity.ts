import { sha256 } from "../../auth/apple-identity.js";
import { FamilyCloudError } from "./cloud-types.js";

export const FAMILY_ACTIVITY_KINDS = ["task", "reading", "video", "screen_time", "creation"] as const;
export type FamilyActivityKind = typeof FAMILY_ACTIVITY_KINDS[number];

export type NormalizedFamilyActivityEvent = {
  clientRef: string;
  kind: FamilyActivityKind;
  occurredAt: string;
  durationSeconds?: number;
  progressPercent?: number;
  displayName: string;
  resourceRef?: string;
  payloadHash: string;
};

export type FamilyActivityWriteResult = {
  acceptedCount: number;
  duplicateCount: number;
  events: Array<{
    clientRef: string;
    status: "created" | "duplicate";
    eventId: string;
  }>;
};

export type ScreenTimeAppDailySourceRow = {
  date: string;
  resourceRef: string;
  durationSeconds: number;
  eventCount: number;
};

export type ScreenTimeAppDailySummaryRow = {
  date: string;
  appRef: string;
  authority: string;
  durationSeconds: number;
  eventCount: number;
};

const SCREEN_TIME_APP_AUTHORITY_REF = /^authority:([a-z0-9_]+):app:([a-f0-9]{32})$/;

export function normalizeScreenTimeAppDailyRows(
  rows: ScreenTimeAppDailySourceRow[],
  limit = 200,
): ScreenTimeAppDailySummaryRow[] {
  const safeLimit = Math.max(0, Math.min(200, Math.trunc(limit)));
  const result: ScreenTimeAppDailySummaryRow[] = [];
  for (const row of rows) {
    if (result.length >= safeLimit || !/^\d{4}-\d{2}-\d{2}$/.test(row.date)) continue;
    const match = SCREEN_TIME_APP_AUTHORITY_REF.exec(row.resourceRef);
    if (!match) continue;
    result.push({
      date: row.date,
      appRef: `app:${match[2]}`,
      authority: match[1],
      durationSeconds: Math.max(0, Math.trunc(row.durationSeconds)),
      eventCount: Math.max(0, Math.trunc(row.eventCount)),
    });
  }
  return result;
}

export function normalizeActivitySummaryWindowDays(
  value: unknown,
  fallback = 90,
): number {
  if (value === undefined || value === null || value === "") return fallback;
  if (typeof value !== "string" || !/^\d{1,2}$/.test(value)) {
    throw new FamilyCloudError("invalid_activity_summary_window");
  }
  const days = Number(value);
  if (!Number.isInteger(days) || days < 1 || days > 90) {
    throw new FamilyCloudError("invalid_activity_summary_window");
  }
  return days;
}

export function normalizeActivitySummaryDate(value: unknown): string | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new FamilyCloudError("invalid_activity_summary_date");
  }
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    throw new FamilyCloudError("invalid_activity_summary_date");
  }
  return value;
}

export function normalizeActivitySummaryTimeZone(
  value: unknown,
  fallback = "UTC",
): string {
  if (value === undefined || value === null || value === "") return fallback;
  if (
    typeof value !== "string" ||
    value.length > 100 ||
    /[\u0000-\u001f\u007f]/.test(value)
  ) {
    throw new FamilyCloudError("invalid_activity_summary_time_zone");
  }
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value }).format();
  } catch {
    throw new FamilyCloudError("invalid_activity_summary_time_zone");
  }
  return value;
}

const EVENT_KEYS = new Set([
  "clientRef",
  "kind",
  "occurredAt",
  "durationSeconds",
  "progressPercent",
  "displayName",
  "resourceRef",
]);
const FORBIDDEN_RESOURCE_SEGMENT = /(^|[:_-])(api[-_]?key|secret|bearer|authorization|familycontrols|managedsettings|applicationtoken|categorytoken|webdomaintoken)([:_-]|$)/i;
const URL_LIKE = /(?:https?:\/\/|file:\/\/|data:|mailto:)/i;
const SECRET_LIKE = /(?:\b(?:api[-_ ]?key|authorization|bearer|familycontrols|managedsettings|applicationtoken|categorytoken|webdomaintoken)\b|\bsk-[A-Za-z0-9_-]{12,}\b)/i;

function record(value: unknown, code: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new FamilyCloudError(code);
  return value as Record<string, unknown>;
}

function strictKeys(value: Record<string, unknown>, allowed: Set<string>): void {
  if (Object.keys(value).some((key) => !allowed.has(key))) {
    throw new FamilyCloudError("forbidden_activity_field");
  }
}

function safeText(value: unknown, code: string, maximum: number): string {
  if (typeof value !== "string") throw new FamilyCloudError(code);
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > maximum || /[\u0000-\u001f\u007f]/.test(trimmed)) {
    throw new FamilyCloudError(code);
  }
  return trimmed;
}

function optionalInteger(value: unknown, code: string, minimum: number, maximum: number): number | undefined {
  if (value === undefined || value === null) return undefined;
  if (!Number.isInteger(value) || Number(value) < minimum || Number(value) > maximum) {
    throw new FamilyCloudError(code);
  }
  return Number(value);
}

function normalizeOccurredAt(value: unknown, now: Date): string {
  const raw = safeText(value, "invalid_activity_occurred_at", 40);
  const timestamp = Date.parse(raw);
  if (!Number.isFinite(timestamp)) throw new FamilyCloudError("invalid_activity_occurred_at");
  const earliest = now.getTime() - 90 * 24 * 60 * 60 * 1_000;
  const latest = now.getTime() + 10 * 60 * 1_000;
  if (timestamp < earliest || timestamp > latest) throw new FamilyCloudError("invalid_activity_occurred_at");
  return new Date(timestamp).toISOString();
}

function payloadHash(event: Omit<NormalizedFamilyActivityEvent, "payloadHash">): string {
  return sha256(JSON.stringify({
    clientRef: event.clientRef,
    kind: event.kind,
    occurredAt: event.occurredAt,
    durationSeconds: event.durationSeconds ?? null,
    progressPercent: event.progressPercent ?? null,
    displayName: event.displayName,
    resourceRef: event.resourceRef ?? null,
  }));
}

export function normalizeFamilyActivityEvent(
  value: unknown,
  now = new Date(),
): NormalizedFamilyActivityEvent {
  const raw = record(value, "invalid_activity_event");
  strictKeys(raw, EVENT_KEYS);

  const clientRef = safeText(raw.clientRef, "invalid_activity_client_ref", 160);
  if (!/^[A-Za-z0-9][A-Za-z0-9:_-]{7,159}$/.test(clientRef)) {
    throw new FamilyCloudError("invalid_activity_client_ref");
  }
  if (!FAMILY_ACTIVITY_KINDS.includes(raw.kind as FamilyActivityKind)) {
    throw new FamilyCloudError("invalid_activity_kind");
  }
  const kind = raw.kind as FamilyActivityKind;
  const occurredAt = normalizeOccurredAt(raw.occurredAt, now);
  const durationSeconds = optionalInteger(raw.durationSeconds, "invalid_activity_duration", 0, 43_200);
  const progressPercent = optionalInteger(raw.progressPercent, "invalid_activity_progress", 0, 100);
  const displayName = safeText(raw.displayName, "invalid_activity_display_name", 160);
  if (URL_LIKE.test(displayName) || SECRET_LIKE.test(displayName)) {
    throw new FamilyCloudError("forbidden_activity_content");
  }

  const resourceRef = raw.resourceRef === undefined || raw.resourceRef === null
    ? undefined : safeText(raw.resourceRef, "invalid_activity_resource_ref", 160);
  if (resourceRef && (
    !/^[A-Za-z0-9][A-Za-z0-9:_-]{0,159}$/.test(resourceRef) ||
    FORBIDDEN_RESOURCE_SEGMENT.test(resourceRef)
  )) {
    throw new FamilyCloudError("forbidden_activity_resource_ref");
  }

  if ((kind === "reading" || kind === "video" || kind === "screen_time") &&
      (durationSeconds === undefined || durationSeconds <= 0)) {
    throw new FamilyCloudError("activity_duration_required");
  }
  if ((kind === "task" || kind === "creation") && durationSeconds === undefined && progressPercent === undefined) {
    throw new FamilyCloudError("activity_measure_required");
  }

  const normalized = {
    clientRef,
    kind,
    occurredAt,
    ...(durationSeconds === undefined ? {} : { durationSeconds }),
    ...(progressPercent === undefined ? {} : { progressPercent }),
    displayName,
    ...(resourceRef === undefined ? {} : { resourceRef }),
  };
  return { ...normalized, payloadHash: payloadHash(normalized) };
}

export function normalizeFamilyActivityPayload(
  value: unknown,
  now = new Date(),
): NormalizedFamilyActivityEvent[] {
  const raw = record(value, "invalid_activity_payload");
  strictKeys(raw, new Set(["event", "events"]));
  const hasEvent = Object.hasOwn(raw, "event");
  const hasEvents = Object.hasOwn(raw, "events");
  if (hasEvent === hasEvents) throw new FamilyCloudError("invalid_activity_payload");
  const values = hasEvent ? [raw.event] : raw.events;
  if (!Array.isArray(values) || values.length < 1 || values.length > 100) {
    throw new FamilyCloudError("invalid_activity_batch_size");
  }
  const events = values.map((event) => normalizeFamilyActivityEvent(event, now));
  if (new Set(events.map((event) => event.clientRef)).size !== events.length) {
    throw new FamilyCloudError("duplicate_activity_client_ref");
  }
  return events;
}
