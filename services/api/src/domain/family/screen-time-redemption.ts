import {
  FamilyCloudError,
  type FamilyScreenTimePolicyPayload,
  type FamilyScreenTimeStatusPayload,
} from "./cloud-types.js";
import { effectiveScreenTimeControlMode } from "./screen-time-control.js";

export type ScreenTimeRedemptionReceipt = {
  redemptionRef: string;
  points: number;
  minutes: number;
  policyRevision: number;
  selectionHash: string;
  controlCommandId: string;
  targetTokenHash: string;
  unlockUntil: string;
};

function requiredText(value: unknown, code: string, maximum: number): string {
  if (typeof value !== "string") throw new FamilyCloudError(code);
  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > maximum) throw new FamilyCloudError(code);
  return normalized;
}

function boundedInteger(value: unknown, code: string, minimum: number, maximum: number): number {
  if (!Number.isSafeInteger(value)) throw new FamilyCloudError(code);
  const result = Number(value);
  if (result < minimum || result > maximum) throw new FamilyCloudError(code);
  return result;
}

export function normalizeScreenTimeRedemptionReceipt(
  value: unknown,
): ScreenTimeRedemptionReceipt {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new FamilyCloudError("invalid_screen_time_redemption");
  }
  const raw = value as Record<string, unknown>;
  const redemptionRef = requiredText(raw.redemptionRef, "invalid_redemption_ref", 64).toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(redemptionRef)) {
    throw new FamilyCloudError("invalid_redemption_ref");
  }
  const selectionHash = requiredText(raw.selectionHash, "invalid_screen_time_selection_hash", 64);
  const targetTokenHash = requiredText(raw.targetTokenHash, "invalid_screen_time_target", 64);
  if (!/^[a-f0-9]{64}$/.test(selectionHash) || !/^[a-f0-9]{64}$/.test(targetTokenHash)) {
    throw new FamilyCloudError("invalid_screen_time_redemption_hash");
  }
  const unlockUntil = requiredText(raw.unlockUntil, "invalid_screen_time_unlock_expiry", 40);
  if (!Number.isFinite(Date.parse(unlockUntil))) {
    throw new FamilyCloudError("invalid_screen_time_unlock_expiry");
  }
  return {
    redemptionRef,
    points: boundedInteger(raw.points, "invalid_screen_time_redemption_points", 1, 1_000_000),
    minutes: boundedInteger(raw.minutes, "invalid_screen_time_redemption_minutes", 15, 240),
    policyRevision: boundedInteger(raw.policyRevision, "invalid_screen_time_policy_revision", 1, 2_147_483_647),
    selectionHash,
    controlCommandId: requiredText(raw.controlCommandId, "invalid_control_command", 160),
    targetTokenHash,
    unlockUntil,
  };
}

export function assertCurrentScreenTimeRedemptionAuthority(
  receipt: ScreenTimeRedemptionReceipt,
  policy: FamilyScreenTimePolicyPayload | undefined,
  status: FamilyScreenTimeStatusPayload | undefined,
  now = new Date(),
): void {
  if (!policy || !status) throw new FamilyCloudError("screen_time_policy_not_ready");
  const control = policy.control;
  if (!control) throw new FamilyCloudError("screen_time_policy_not_ready");
  if (effectiveScreenTimeControlMode(policy, now) !== "locked") {
    throw new FamilyCloudError("screen_time_policy_not_locked");
  }
  if (status.authorization !== "approved" || status.enforcement !== "applied") {
    throw new FamilyCloudError("screen_time_device_not_enforcing");
  }
  if (receipt.policyRevision !== policy.revision ||
      receipt.policyRevision !== status.appliedPolicyRevision ||
      receipt.selectionHash !== policy.selectionHash ||
      receipt.selectionHash !== status.appliedSelectionHash ||
      receipt.controlCommandId !== control.commandId ||
      receipt.controlCommandId !== status.appliedControlCommandId ||
      status.controlMode !== "locked") {
    throw new FamilyCloudError("stale_screen_time_device_receipt");
  }
}

export function assertCurrentScreenTimeRedemption(
  receipt: ScreenTimeRedemptionReceipt,
  policy: FamilyScreenTimePolicyPayload | undefined,
  status: FamilyScreenTimeStatusPayload | undefined,
  now = new Date(),
): void {
  assertCurrentScreenTimeRedemptionAuthority(receipt, policy, status, now);
  const unlockUntil = new Date(receipt.unlockUntil);
  const expectedDuration = receipt.minutes * 60 * 1_000;
  const actualDuration = unlockUntil.getTime() - now.getTime();
  if (actualDuration < expectedDuration - 60_000 || actualDuration > expectedDuration + 60_000) {
    throw new FamilyCloudError("invalid_screen_time_unlock_expiry");
  }
}
