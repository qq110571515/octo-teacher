import assert from "node:assert/strict";
import test from "node:test";
import { sha256 } from "../../auth/apple-identity.js";
import { FamilyCloudError } from "./cloud-types.js";
import {
  normalizeScreenTimeCatalogUpload,
  normalizeScreenTimePolicy,
  normalizeScreenTimeSelection,
  normalizeScreenTimeStatus,
  normalizeStoredScreenTimeCatalog,
  normalizeStoredScreenTimePolicy,
} from "./postgres-family-cloud.js";

test("child Screen Time catalog preserves opaque tokens and rejects client ownership fields", () => {
  const selectionData = Buffer.from("child-device-catalog").toString("base64");
  const catalog = normalizeScreenTimeCatalogUpload({
    schemaVersion: 1,
    revision: 999,
    sourceDevicePublicRef: "attacker-device",
    selectionData,
    selectionHash: sha256(selectionData),
    applicationCount: 12,
    categoryCount: 2,
    webDomainCount: 0,
    capturedAt: "2026-08-01T17:00:00.000Z",
  });

  assert.equal(catalog.applicationCount, 12);
  assert.equal("revision" in catalog, false);
  assert.equal("sourceDevicePublicRef" in catalog, false);
});

test("stored Screen Time catalog validates its server-bound device and revision", () => {
  const selectionData = Buffer.from("stored-child-catalog").toString("base64");
  const catalog = normalizeStoredScreenTimeCatalog({
    schemaVersion: 1,
    revision: 4,
    sourceDevicePublicRef: "device_123",
    selectionData,
    selectionHash: sha256(selectionData),
    applicationCount: 8,
    categoryCount: 1,
    webDomainCount: 0,
    capturedAt: "2026-08-01T17:00:00.000Z",
  });

  assert.equal(catalog.revision, 4);
  assert.equal(catalog.sourceDevicePublicRef, "device_123");
  assert.throws(() => normalizeStoredScreenTimeCatalog({
    ...catalog,
    sourceDevicePublicRef: "",
  }), FamilyCloudError);
});

test("screen time policy accepts an opaque bounded selection and replaces client timestamps", () => {
  const selectionData = Buffer.from("opaque-selection").toString("base64");
  const policy = normalizeScreenTimePolicy({
    schemaVersion: 3,
    revision: 3,
    selectionData,
    selectionHash: sha256(selectionData),
    applicationCount: 2,
    categoryCount: 0,
    webDomainCount: 0,
    updatedAt: "untrusted-client-time",
  });

  assert.equal(policy.schemaVersion, 3);
  assert.equal(policy.revision, 3);
  assert.equal(policy.applicationCount, 2);
  assert.match(policy.updatedAt, /^\d{4}-\d{2}-\d{2}T/);
});

test("guardian policy preserves a valid child catalog binding", () => {
  const selectionData = Buffer.from("catalog-derived-policy").toString("base64");
  const catalogHash = sha256(Buffer.from("catalog-source").toString("base64"));
  const policy = normalizeScreenTimePolicy({
    schemaVersion: 3,
    revision: 6,
    selectionData,
    selectionHash: sha256(selectionData),
    applicationCount: 3,
    categoryCount: 0,
    webDomainCount: 0,
    catalogBinding: { revision: 2, selectionHash: catalogHash },
  });

  assert.deepEqual(policy.catalogBinding, { revision: 2, selectionHash: catalogHash });
  assert.throws(() => normalizeScreenTimePolicy({
    ...policy,
    catalogBinding: { revision: 2, selectionHash: "not-a-hash" },
  }), FamilyCloudError);
});

test("guardian Screen Time selection accepts only the opaque baseline fields", () => {
  const selectionData = Buffer.from("guardian-selection").toString("base64");
  const selection = normalizeScreenTimeSelection({
    schemaVersion: 3,
    revision: 99,
    selectionData,
    selectionHash: sha256(selectionData),
    applicationCount: 5,
    categoryCount: 2,
    webDomainCount: 1,
    control: {
      schemaVersion: 1,
      commandId: "untrusted-client-control",
      mode: "unlocked",
      issuedAt: "2026-07-31T00:00:00.000Z",
      unlockUntil: "2099-01-01T00:00:00.000Z",
    },
  });

  assert.deepEqual(selection, {
    schemaVersion: 3,
    selectionData,
    selectionHash: sha256(selectionData),
    applicationCount: 5,
    categoryCount: 2,
    webDomainCount: 1,
  });
  assert.equal("control" in selection, false);
  assert.equal("revision" in selection, false);
});

test("screen time policy rejects malformed or empty selections", () => {
  assert.throws(() => normalizeScreenTimePolicy({
    schemaVersion: 3,
    revision: 1,
    selectionData: "not-base64!",
    selectionHash: "0".repeat(64),
    applicationCount: 1,
    categoryCount: 0,
    webDomainCount: 0,
  }), FamilyCloudError);
  assert.throws(() => normalizeScreenTimePolicy({
    schemaVersion: 3,
    revision: 1,
    selectionData: Buffer.from("opaque-selection").toString("base64"),
    selectionHash: "0".repeat(64),
    applicationCount: 0,
    categoryCount: 0,
    webDomainCount: 0,
  }), FamilyCloudError);
});

test("stored legacy policies upgrade to v3 without changing the opaque selection", () => {
  const selectionData = Buffer.from("legacy-opaque-selection").toString("base64");
  const policy = normalizeStoredScreenTimePolicy({
    schemaVersion: 1,
    revision: 2,
    selectionData,
    applicationCount: 0,
    categoryCount: 2,
    webDomainCount: 0,
    updatedAt: "2026-07-13T06:45:13.559Z",
  });

  assert.equal(policy.schemaVersion, 3);
  assert.equal(policy.selectionData, selectionData);
  assert.equal(policy.selectionHash, sha256(selectionData));
  assert.equal(policy.control?.mode, "locked");
  assert.equal(policy.control?.commandId, `policy:2:${sha256(selectionData).slice(0, 16)}`);
});

test("stored v3 policies preserve an active remote unlock command", () => {
  const selectionData = Buffer.from("current-opaque-selection").toString("base64");
  const policy = normalizeStoredScreenTimePolicy({
    schemaVersion: 3,
    revision: 8,
    selectionData,
    selectionHash: sha256(selectionData),
    applicationCount: 4,
    categoryCount: 1,
    webDomainCount: 0,
    control: {
      schemaVersion: 1,
      commandId: "control:test",
      mode: "unlocked",
      issuedAt: "2026-07-29T20:00:00.000Z",
      unlockUntil: "2026-07-29T20:30:00.000Z",
    },
    updatedAt: "2026-07-29T20:00:00.000Z",
  });

  assert.equal(policy.control?.commandId, "control:test");
  assert.equal(policy.control?.mode, "unlocked");
  assert.equal(policy.control?.unlockUntil, "2026-07-29T20:30:00.000Z");
});

test("child enforcement acknowledgement requires authorization and preserves a legacy revision", () => {
  const selectionHash = "a".repeat(64);
  const status = normalizeScreenTimeStatus({
    authorization: "approved",
    enforcement: "applied",
    appliedPolicyRevision: 7,
    appliedSelectionHash: selectionHash,
    appliedControlCommandId: "policy:7:test",
    controlMode: "locked",
    applicationCount: 3,
    categoryCount: 1,
    webDomainCount: 0,
  });
  assert.equal(status.appliedPolicyRevision, 7);
  assert.equal(status.applicationCount, 3);
  assert.equal(status.categoryCount, 1);
  assert.throws(() => normalizeScreenTimeStatus({
    authorization: "not_requested",
    enforcement: "applied",
  }), FamilyCloudError);
});

test("an applied child receipt must identify the exact guardian policy and command", () => {
  assert.throws(() => normalizeScreenTimeStatus({
    authorization: "approved",
    enforcement: "applied",
    applicationCount: 4,
    categoryCount: 0,
    webDomainCount: 0,
  }), /incomplete_screen_time_applied_receipt/);
});
