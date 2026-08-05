import assert from "node:assert/strict";
import test from "node:test";
import { sha256 } from "../../auth/apple-identity.js";
import { FamilyCloudError, type FamilyScreenTimePolicyPayload, type FamilyScreenTimeStatusPayload } from "./cloud-types.js";
import {
  assertCurrentScreenTimeRedemption,
  assertCurrentScreenTimeRedemptionAuthority,
  normalizeScreenTimeRedemptionReceipt,
} from "./screen-time-redemption.js";

const now = new Date("2026-08-01T18:00:00.000Z");
const selectionHash = sha256("opaque-selection");
const receipt = normalizeScreenTimeRedemptionReceipt({
  redemptionRef: "f44734ba-d42a-4ab6-b5d8-2b93cfdad7f2",
  points: 15,
  minutes: 15,
  policyRevision: 8,
  selectionHash,
  controlCommandId: "control:locked:8",
  targetTokenHash: sha256("opaque-app-token"),
  unlockUntil: "2026-08-01T18:15:00.000Z",
});
const policy: FamilyScreenTimePolicyPayload = {
  schemaVersion: 3,
  revision: 8,
  selectionData: "b3BhcXVlLXNlbGVjdGlvbg==",
  selectionHash,
  applicationCount: 4,
  categoryCount: 1,
  webDomainCount: 0,
  control: {
    schemaVersion: 1,
    commandId: "control:locked:8",
    mode: "locked",
    issuedAt: now.toISOString(),
  },
  updatedAt: now.toISOString(),
};
const status: FamilyScreenTimeStatusPayload = {
  authorization: "approved",
  enforcement: "applied",
  appliedPolicyRevision: 8,
  appliedSelectionHash: selectionHash,
  appliedControlCommandId: "control:locked:8",
  controlMode: "locked",
  applicationCount: 4,
  categoryCount: 1,
  webDomainCount: 0,
  updatedAt: now.toISOString(),
};

test("Screen Time redemption accepts only an exact current device receipt", () => {
  assert.doesNotThrow(() => assertCurrentScreenTimeRedemption(receipt, policy, status, now));
});

test("commit authority remains valid after the fresh unlock-window check has elapsed", () => {
  const delayedCommit = new Date(now.getTime() + 2 * 60 * 1_000);
  assert.throws(
    () => assertCurrentScreenTimeRedemption(receipt, policy, status, delayedCommit),
    (error) => error instanceof FamilyCloudError && error.code === "invalid_screen_time_unlock_expiry",
  );
  assert.doesNotThrow(() => assertCurrentScreenTimeRedemptionAuthority(receipt, policy, status));
});

test("Screen Time redemption rejects the stale applied receipt that caused false point spends", () => {
  assert.throws(
    () => assertCurrentScreenTimeRedemption(receipt, policy, {
      ...status,
      appliedPolicyRevision: 2,
      appliedSelectionHash: sha256("old-selection"),
      appliedControlCommandId: "policy:2:old",
    }, now),
    (error) => error instanceof FamilyCloudError && error.code === "stale_screen_time_device_receipt",
  );
});

test("Screen Time redemption rejects category unlocks while guardian control is already unlocked", () => {
  assert.throws(
    () => assertCurrentScreenTimeRedemption(receipt, {
      ...policy,
      control: {
        schemaVersion: 1,
        commandId: "control:unlocked:9",
        mode: "unlocked",
        issuedAt: now.toISOString(),
        unlockUntil: "2026-08-01T18:30:00.000Z",
      },
    }, status, now),
    (error) => error instanceof FamilyCloudError && error.code === "screen_time_policy_not_locked",
  );
});

test("an expired guardian unlock is effectively locked and can start a paid app window", () => {
  const expiredPolicy: FamilyScreenTimePolicyPayload = {
    ...policy,
    control: {
      schemaVersion: 1,
      commandId: policy.control!.commandId,
      mode: "unlocked",
      issuedAt: "2026-08-01T17:00:00.000Z",
      unlockUntil: "2026-08-01T17:30:00.000Z",
    },
  };
  assert.doesNotThrow(() => assertCurrentScreenTimeRedemption(
    receipt,
    expiredPolicy,
    status,
    now,
  ));
});
