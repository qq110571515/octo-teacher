import { createHash } from "node:crypto";
import { FamilyCloudError } from "./cloud-types.js";

export const FAMILY_TASK_SYNC_PAGE_LIMIT = 200;

type TaskStatus = "assigned" | "started" | "submitted" | "approved" | "rejected" | "cancelled";

export function parseFamilyTaskCursor(value: unknown): number {
  if (value === undefined || value === null || value === "") return 0;
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) throw new FamilyCloudError("invalid_sync_cursor");
  return parsed;
}

export function normalizeMutationRef(value: unknown): string {
  if (typeof value !== "string") throw new FamilyCloudError("invalid_mutation_ref");
  const normalized = value.trim();
  if (normalized.length < 8 || normalized.length > 160 || !/^[A-Za-z0-9:._-]+$/.test(normalized)) {
    throw new FamilyCloudError("invalid_mutation_ref");
  }
  return normalized;
}

export function legacyMutationRef(prefix: string, payload: unknown): string {
  const digest = createHash("sha256").update(JSON.stringify(payload)).digest("hex");
  return `${prefix}:${digest}`;
}

export function resolveGuardianTaskStatus(current: TaskStatus, proposed: TaskStatus): TaskStatus {
  if (current === "approved" || current === "cancelled") return current;
  if (["approved", "rejected", "cancelled"].includes(proposed)) return proposed;
  if (current === "submitted" && (proposed === "assigned" || proposed === "started")) return current;
  return proposed;
}

export function canWithdrawChildTask(current: TaskStatus): boolean {
  return current === "submitted";
}
