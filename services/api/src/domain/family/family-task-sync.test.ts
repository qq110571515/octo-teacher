import assert from "node:assert/strict";
import test from "node:test";
import { FamilyCloudError } from "./cloud-types.js";
import {
  canWithdrawChildTask,
  legacyMutationRef,
  normalizeMutationRef,
  parseFamilyTaskCursor,
  resolveGuardianTaskStatus,
} from "./family-task-sync.js";

test("task sync cursor accepts only non-negative safe integers", () => {
  assert.equal(parseFamilyTaskCursor(undefined), 0);
  assert.equal(parseFamilyTaskCursor("42"), 42);
  assert.throws(() => parseFamilyTaskCursor("-1"), FamilyCloudError);
  assert.throws(() => parseFamilyTaskCursor("1.5"), FamilyCloudError);
});

test("mutation refs are opaque, bounded, and transport safe", () => {
  assert.equal(normalizeMutationRef(" child-submit:abc_123 "), "child-submit:abc_123");
  assert.throws(() => normalizeMutationRef("short"), FamilyCloudError);
  assert.throws(() => normalizeMutationRef("contains a space"), FamilyCloudError);
});

test("legacy mutation refs are deterministic during a rolling client upgrade", () => {
  const first = legacyMutationRef("guardian-legacy", { tasks: [{ id: "one" }] });
  const second = legacyMutationRef("guardian-legacy", { tasks: [{ id: "one" }] });
  assert.equal(first, second);
  assert.match(first, /^guardian-legacy:[0-9a-f]{64}$/);
});

test("guardian sync cannot accidentally reopen child submissions or approvals", () => {
  assert.equal(resolveGuardianTaskStatus("submitted", "assigned"), "submitted");
  assert.equal(resolveGuardianTaskStatus("approved", "started"), "approved");
  assert.equal(resolveGuardianTaskStatus("approved", "rejected"), "approved");
  assert.equal(resolveGuardianTaskStatus("approved", "cancelled"), "approved");
  assert.equal(resolveGuardianTaskStatus("cancelled", "approved"), "cancelled");
  assert.equal(resolveGuardianTaskStatus("submitted", "approved"), "approved");
});

test("only a pending guardian review can be withdrawn by the child", () => {
  assert.equal(canWithdrawChildTask("submitted"), true);
  assert.equal(canWithdrawChildTask("assigned"), false);
  assert.equal(canWithdrawChildTask("started"), false);
  assert.equal(canWithdrawChildTask("approved"), false);
  assert.equal(canWithdrawChildTask("rejected"), false);
  assert.equal(canWithdrawChildTask("cancelled"), false);
});
