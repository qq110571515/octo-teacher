import {
  FamilyCloudError,
  type FamilyScreenTimeEmergencyPayload,
} from "./cloud-types.js";

export const SCREEN_TIME_EMERGENCY_REQUEST_TTL_MS = 30 * 60 * 1_000;
export const SCREEN_TIME_EMERGENCY_APPROVAL_TTL_MS = 10 * 60 * 1_000;
export const SCREEN_TIME_EMERGENCY_MAX_MINUTES = 60;

export type ChildScreenTimeEmergencyAction = {
  action: "request" | "activate" | "complete" | "expire";
  requestId: string;
  reason?: string;
  minutes?: number;
  sessionEndsAt?: string;
};

export type GuardianScreenTimeEmergencyAction = {
  action: "approve" | "deny";
  requestId: string;
  minutes?: number;
};

const REQUEST_ID_PATTERN = /^[A-Za-z0-9:_-]{8,160}$/;

function iso(date: Date): string {
  if (!Number.isFinite(date.getTime())) throw new FamilyCloudError("invalid_emergency_timestamp");
  return date.toISOString();
}

function parseTimestamp(value: unknown, code = "invalid_screen_time_emergency"): number {
  if (typeof value !== "string") throw new FamilyCloudError(code);
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) throw new FamilyCloudError(code);
  return timestamp;
}

function requireTimestampOrder(previous: number, next: number): void {
  if (next < previous) throw new FamilyCloudError("invalid_screen_time_emergency");
}

function requestId(value: unknown): string {
  if (typeof value !== "string" || !REQUEST_ID_PATTERN.test(value)) {
    throw new FamilyCloudError("invalid_emergency_request_id");
  }
  return value;
}

function reason(value: unknown): string {
  if (typeof value !== "string") throw new FamilyCloudError("invalid_emergency_reason");
  const normalized = value.trim();
  if (!normalized || normalized.length > 280) throw new FamilyCloudError("invalid_emergency_reason");
  return normalized;
}

function minutes(value: unknown): number {
  if (!Number.isInteger(value) || Number(value) < 1 || Number(value) > SCREEN_TIME_EMERGENCY_MAX_MINUTES) {
    throw new FamilyCloudError("invalid_emergency_minutes");
  }
  return Number(value);
}

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new FamilyCloudError("invalid_screen_time_emergency");
  }
  return value as Record<string, unknown>;
}

export function idleScreenTimeEmergency(now = new Date()): FamilyScreenTimeEmergencyPayload {
  return { schemaVersion: 1, status: "idle", updatedAt: iso(now) };
}

export function normalizeStoredScreenTimeEmergency(value: unknown): FamilyScreenTimeEmergencyPayload {
  const raw = object(value);
  if (raw.schemaVersion !== 1 || typeof raw.status !== "string") {
    throw new FamilyCloudError("invalid_screen_time_emergency");
  }
  const updatedAt = typeof raw.updatedAt === "string" ? raw.updatedAt : "";
  if (raw.status === "idle") {
    if (updatedAt) parseTimestamp(updatedAt);
    return { schemaVersion: 1, status: "idle", updatedAt };
  }

  const base = {
    schemaVersion: 1 as const,
    requestId: requestId(raw.requestId),
    reason: reason(raw.reason),
    minutes: minutes(raw.minutes),
    requestedAt: String(raw.requestedAt),
    updatedAt,
  };
  const requestedAtMs = parseTimestamp(base.requestedAt);
  const updatedAtMs = parseTimestamp(base.updatedAt);
  requireTimestampOrder(requestedAtMs, updatedAtMs);

  if (raw.status === "requested") return { ...base, status: "requested" };
  if (raw.status === "denied") {
    const decidedAt = String(raw.decidedAt);
    const decidedAtMs = parseTimestamp(decidedAt);
    requireTimestampOrder(requestedAtMs, decidedAtMs);
    requireTimestampOrder(decidedAtMs, updatedAtMs);
    return { ...base, status: "denied", decidedAt };
  }
  if (raw.status === "expired" && raw.expirationReason === "request_timeout") {
    const expiredAt = String(raw.expiredAt);
    const expiredAtMs = parseTimestamp(expiredAt);
    requireTimestampOrder(requestedAtMs + SCREEN_TIME_EMERGENCY_REQUEST_TTL_MS, expiredAtMs);
    requireTimestampOrder(expiredAtMs, updatedAtMs);
    return { ...base, status: "expired", expiredAt, expirationReason: "request_timeout" };
  }

  const decidedAt = String(raw.decidedAt);
  const approvalExpiresAt = String(raw.approvalExpiresAt);
  const decidedAtMs = parseTimestamp(decidedAt);
  const approvalExpiresAtMs = parseTimestamp(approvalExpiresAt);
  requireTimestampOrder(requestedAtMs, decidedAtMs);
  if (approvalExpiresAtMs <= decidedAtMs) throw new FamilyCloudError("invalid_screen_time_emergency");
  const approved = { ...base, decidedAt, approvalExpiresAt };
  if (raw.status === "approved") {
    requireTimestampOrder(decidedAtMs, updatedAtMs);
    return { ...approved, status: "approved" };
  }

  if (raw.status === "expired" && raw.expirationReason === "approval_timeout") {
    const expiredAt = String(raw.expiredAt);
    const expiredAtMs = parseTimestamp(expiredAt);
    requireTimestampOrder(approvalExpiresAtMs, expiredAtMs);
    requireTimestampOrder(expiredAtMs, updatedAtMs);
    return { ...approved, status: "expired", expiredAt, expirationReason: "approval_timeout" };
  }

  const activatedAt = String(raw.activatedAt);
  const sessionEndsAt = String(raw.sessionEndsAt);
  const activatedAtMs = parseTimestamp(activatedAt);
  const sessionEndsAtMs = parseTimestamp(sessionEndsAt);
  requireTimestampOrder(decidedAtMs, activatedAtMs);
  if (activatedAtMs >= approvalExpiresAtMs || sessionEndsAtMs <= activatedAtMs ||
      sessionEndsAtMs - activatedAtMs !== base.minutes * 60_000) {
    throw new FamilyCloudError("invalid_screen_time_emergency");
  }
  const active = { ...approved, activatedAt, sessionEndsAt };
  if (raw.status === "active") {
    requireTimestampOrder(activatedAtMs, updatedAtMs);
    return { ...active, status: "active" };
  }
  if (raw.status === "completed") {
    const completedAt = String(raw.completedAt);
    const completedAtMs = parseTimestamp(completedAt);
    requireTimestampOrder(activatedAtMs, completedAtMs);
    if (completedAtMs > sessionEndsAtMs) throw new FamilyCloudError("invalid_screen_time_emergency");
    requireTimestampOrder(completedAtMs, updatedAtMs);
    return { ...active, status: "completed", completedAt };
  }
  if (raw.status === "expired" && raw.expirationReason === "session_timeout") {
    const expiredAt = String(raw.expiredAt);
    const expiredAtMs = parseTimestamp(expiredAt);
    requireTimestampOrder(sessionEndsAtMs, expiredAtMs);
    requireTimestampOrder(expiredAtMs, updatedAtMs);
    return { ...active, status: "expired", expiredAt, expirationReason: "session_timeout" };
  }
  throw new FamilyCloudError("invalid_screen_time_emergency");
}

export function assertScreenTimeEmergencyScope(input: {
  actorFamilyId: string;
  childFamilyId: string;
  childProfileId: string;
  actorChildProfileId?: string;
}): void {
  if (input.actorFamilyId !== input.childFamilyId ||
      (input.actorChildProfileId !== undefined && input.actorChildProfileId !== input.childProfileId)) {
    throw new FamilyCloudError("screen_time_emergency_access_denied");
  }
}

function sameRequest(
  current: FamilyScreenTimeEmergencyPayload,
  requestedId: string,
): current is Exclude<FamilyScreenTimeEmergencyPayload, { status: "idle" }> {
  return current.status !== "idle" && current.requestId === requestedId;
}

function terminal(status: FamilyScreenTimeEmergencyPayload["status"]): boolean {
  return status === "idle" || status === "denied" || status === "completed" || status === "expired";
}

export function applyChildScreenTimeEmergencyAction(
  currentValue: unknown,
  inputValue: unknown,
  now = new Date(),
): FamilyScreenTimeEmergencyPayload {
  const current = normalizeStoredScreenTimeEmergency(currentValue);
  const input = object(inputValue) as ChildScreenTimeEmergencyAction;
  const nowMs = now.getTime();
  const nowISO = iso(now);
  const requestedId = requestId(input.requestId);
  if (!["request", "activate", "complete", "expire"].includes(input.action)) {
    throw new FamilyCloudError("invalid_emergency_child_action");
  }

  if (input.action === "request") {
    if (sameRequest(current, requestedId)) return current;
    if (!terminal(current.status)) throw new FamilyCloudError("emergency_request_in_progress");
    return {
      schemaVersion: 1,
      status: "requested",
      requestId: requestedId,
      reason: reason(input.reason),
      minutes: minutes(input.minutes),
      requestedAt: nowISO,
      updatedAt: nowISO,
    };
  }

  // sessionEndsAt is accepted for wire compatibility but is never trusted; the server derives it on activation.

  if (!sameRequest(current, requestedId)) throw new FamilyCloudError("emergency_request_mismatch");
  if (input.action === "activate") {
    if (current.status === "active" || current.status === "completed") return current;
    if (current.status !== "approved") throw new FamilyCloudError("invalid_emergency_transition");
    if (nowMs >= parseTimestamp(current.approvalExpiresAt, "emergency_approval_expired")) {
      throw new FamilyCloudError("emergency_approval_expired");
    }
    return {
      ...current,
      status: "active",
      activatedAt: nowISO,
      sessionEndsAt: new Date(nowMs + current.minutes * 60_000).toISOString(),
      updatedAt: nowISO,
    };
  }
  if (input.action === "complete") {
    if (current.status === "completed") return current;
    if (current.status !== "active") throw new FamilyCloudError("invalid_emergency_transition");
    if (nowMs > parseTimestamp(current.sessionEndsAt, "emergency_session_expired")) {
      throw new FamilyCloudError("emergency_session_expired");
    }
    return { ...current, status: "completed", completedAt: nowISO, updatedAt: nowISO };
  }

  if (current.status === "expired") return current;
  if (current.status === "requested") {
    if (nowMs < parseTimestamp(current.requestedAt) + SCREEN_TIME_EMERGENCY_REQUEST_TTL_MS) {
      throw new FamilyCloudError("emergency_request_not_expired");
    }
    return { ...current, status: "expired", expiredAt: nowISO, expirationReason: "request_timeout", updatedAt: nowISO };
  }
  if (current.status === "approved") {
    if (nowMs < parseTimestamp(current.approvalExpiresAt)) {
      throw new FamilyCloudError("emergency_approval_not_expired");
    }
    return { ...current, status: "expired", expiredAt: nowISO, expirationReason: "approval_timeout", updatedAt: nowISO };
  }
  if (current.status === "active") {
    if (nowMs < parseTimestamp(current.sessionEndsAt)) {
      throw new FamilyCloudError("emergency_session_not_expired");
    }
    return { ...current, status: "expired", expiredAt: nowISO, expirationReason: "session_timeout", updatedAt: nowISO };
  }
  throw new FamilyCloudError("invalid_emergency_transition");
}

export function applyGuardianScreenTimeEmergencyAction(
  currentValue: unknown,
  inputValue: unknown,
  now = new Date(),
): FamilyScreenTimeEmergencyPayload {
  const current = normalizeStoredScreenTimeEmergency(currentValue);
  const input = object(inputValue) as GuardianScreenTimeEmergencyAction;
  const requestedId = requestId(input.requestId);
  const nowMs = now.getTime();
  const nowISO = iso(now);
  if (!["approve", "deny"].includes(input.action)) {
    throw new FamilyCloudError("invalid_emergency_guardian_action");
  }
  if (!sameRequest(current, requestedId)) throw new FamilyCloudError("emergency_request_mismatch");
  if ((input.action === "approve" && ["approved", "active", "completed"].includes(current.status)) ||
      (input.action === "deny" && current.status === "denied")) {
    return current;
  }
  if (current.status !== "requested") throw new FamilyCloudError("invalid_emergency_transition");
  if (nowMs >= parseTimestamp(current.requestedAt) + SCREEN_TIME_EMERGENCY_REQUEST_TTL_MS) {
    throw new FamilyCloudError("emergency_request_expired");
  }
  if (input.action === "deny") {
    return { ...current, status: "denied", decidedAt: nowISO, updatedAt: nowISO };
  }
  const approvedMinutes = input.minutes === undefined ? current.minutes : minutes(input.minutes);
  return {
    ...current,
    status: "approved",
    minutes: approvedMinutes,
    decidedAt: nowISO,
    approvalExpiresAt: new Date(nowMs + SCREEN_TIME_EMERGENCY_APPROVAL_TTL_MS).toISOString(),
    updatedAt: nowISO,
  };
}
