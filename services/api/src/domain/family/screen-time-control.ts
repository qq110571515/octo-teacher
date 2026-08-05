import { randomUUID } from "node:crypto";
import {
  FamilyCloudError,
  type FamilyScreenTimeCatalogPayload,
  type FamilyScreenTimePolicyPayload,
} from "./cloud-types.js";

export type GuardianScreenTimeControlAction = {
  action: "lock" | "unlock";
  minutes?: number;
};

export function screenTimePolicyCanApplyOnDevice(
  policy: FamilyScreenTimePolicyPayload,
  catalog: FamilyScreenTimeCatalogPayload | undefined,
  devicePublicRef: string,
): boolean {
  if (policy.catalogBinding === undefined) return true;
  return catalog?.sourceDevicePublicRef === devicePublicRef;
}

export function effectiveScreenTimeControlMode(
  policy: FamilyScreenTimePolicyPayload,
  now = new Date(),
): "locked" | "unlocked" {
  const control = policy.control;
  if (control?.mode !== "unlocked") return "locked";
  const unlockUntil = control.unlockUntil === undefined
    ? Number.NaN
    : Date.parse(control.unlockUntil);
  return Number.isFinite(unlockUntil) && unlockUntil > now.getTime()
    ? "unlocked"
    : "locked";
}

function requireAction(value: unknown): GuardianScreenTimeControlAction {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new FamilyCloudError("invalid_screen_time_control");
  }
  const raw = value as Record<string, unknown>;
  if (raw.action === "lock") return { action: "lock" };
  if (raw.action !== "unlock" || !Number.isInteger(raw.minutes)) {
    throw new FamilyCloudError("invalid_screen_time_control");
  }
  const minutes = Number(raw.minutes);
  if (minutes < 15 || minutes > 120) {
    throw new FamilyCloudError("invalid_screen_time_control_minutes");
  }
  return { action: "unlock", minutes };
}

export function applyGuardianScreenTimeControl(
  currentPolicy: FamilyScreenTimePolicyPayload,
  input: unknown,
  now = new Date(),
  commandId = `control:${randomUUID()}`,
): FamilyScreenTimePolicyPayload {
  const action = requireAction(input);
  if (!Number.isFinite(now.getTime())) {
    throw new FamilyCloudError("invalid_screen_time_control_timestamp");
  }
  const issuedAt = now.toISOString();
  const revision = currentPolicy.revision + 1;
  if (!Number.isSafeInteger(revision) || revision > 2_147_483_647) {
    throw new FamilyCloudError("screen_time_policy_revision_exhausted");
  }

  return {
    ...currentPolicy,
    revision,
    control: action.action === "lock"
      ? {
          schemaVersion: 1,
          commandId,
          mode: "locked",
          issuedAt,
        }
      : {
          schemaVersion: 1,
          commandId,
          mode: "unlocked",
          issuedAt,
          unlockUntil: new Date(now.getTime() + action.minutes! * 60_000).toISOString(),
        },
    updatedAt: issuedAt,
  };
}
