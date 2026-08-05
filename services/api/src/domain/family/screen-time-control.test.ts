import assert from "node:assert/strict";
import test from "node:test";
import { sha256 } from "../../auth/apple-identity.js";
import {
  FamilyCloudError,
  type FamilyScreenTimeCatalogPayload,
  type FamilyScreenTimePolicyPayload,
} from "./cloud-types.js";
import {
  applyGuardianScreenTimeControl,
  screenTimePolicyCanApplyOnDevice,
} from "./screen-time-control.js";

const selectionData = Buffer.from("opaque-family-selection").toString("base64");
const policy: FamilyScreenTimePolicyPayload = {
  schemaVersion: 3,
  revision: 8,
  selectionData,
  selectionHash: sha256(selectionData),
  applicationCount: 12,
  categoryCount: 1,
  webDomainCount: 0,
  updatedAt: "2026-07-29T20:00:00.000Z",
};

test("guardian lock preserves the opaque selection and advances the command revision", () => {
  const next = applyGuardianScreenTimeControl(
    policy,
    { action: "lock" },
    new Date("2026-07-29T20:01:00.000Z"),
    "control:lock-1",
  );
  assert.equal(next.revision, 9);
  assert.equal(next.selectionData, policy.selectionData);
  assert.equal(next.selectionHash, policy.selectionHash);
  assert.deepEqual(next.control, {
    schemaVersion: 1,
    commandId: "control:lock-1",
    mode: "locked",
    issuedAt: "2026-07-29T20:01:00.000Z",
  });
});

test("guardian unlock derives its expiry from server time", () => {
  const next = applyGuardianScreenTimeControl(
    policy,
    { action: "unlock", minutes: 30 },
    new Date("2026-07-29T20:01:00.000Z"),
    "control:unlock-1",
  );
  assert.equal(next.control?.mode, "unlocked");
  assert.equal(next.control?.unlockUntil, "2026-07-29T20:31:00.000Z");
});

test("guardian unlock rejects unsafe durations", () => {
  assert.throws(
    () => applyGuardianScreenTimeControl(policy, { action: "unlock", minutes: 5 }),
    FamilyCloudError,
  );
  assert.throws(
    () => applyGuardianScreenTimeControl(policy, { action: "unlock", minutes: 121 }),
    FamilyCloudError,
  );
});

test("catalog-bound policies apply only on the child device that captured the tokens", () => {
  const catalog: FamilyScreenTimeCatalogPayload = {
    schemaVersion: 1,
    revision: 3,
    selectionData,
    selectionHash: sha256(selectionData),
    applicationCount: 12,
    categoryCount: 0,
    webDomainCount: 0,
    capturedAt: "2026-07-29T20:00:00.000Z",
    sourceDevicePublicRef: "device-a",
  };
  const boundPolicy: FamilyScreenTimePolicyPayload = {
    ...policy,
    catalogBinding: { revision: catalog.revision, selectionHash: catalog.selectionHash },
  };

  assert.equal(screenTimePolicyCanApplyOnDevice(boundPolicy, catalog, "device-a"), true);
  assert.equal(screenTimePolicyCanApplyOnDevice(boundPolicy, catalog, "device-b"), false);
  assert.equal(screenTimePolicyCanApplyOnDevice(boundPolicy, undefined, "device-a"), false);
  assert.equal(screenTimePolicyCanApplyOnDevice(policy, undefined, "device-b"), true);
});
