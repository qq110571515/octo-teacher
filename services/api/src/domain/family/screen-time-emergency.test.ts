import assert from "node:assert/strict";
import test from "node:test";
import { FamilyCloudError } from "./cloud-types.js";
import {
  applyChildScreenTimeEmergencyAction,
  applyGuardianScreenTimeEmergencyAction,
  assertScreenTimeEmergencyScope,
  idleScreenTimeEmergency,
} from "./screen-time-emergency.js";

const REQUEST_ID = "emergency:req:0001";
const START = new Date("2026-07-14T12:00:00.000Z");

function after(minutes: number): Date {
  return new Date(START.getTime() + minutes * 60_000);
}

function throwsCode(run: () => unknown, code: string): void {
  assert.throws(run, (error) => error instanceof FamilyCloudError && error.code === code);
}

test("emergency unlock follows requested -> approved -> active -> completed with server timestamps", () => {
  let state = idleScreenTimeEmergency(START);
  state = applyChildScreenTimeEmergencyAction(state, {
    action: "request",
    requestId: REQUEST_ID,
    reason: "Need to call my parent",
    minutes: 30,
    sessionEndsAt: "2099-01-01T00:00:00.000Z",
  }, START);
  assert.equal(state.status, "requested");
  assert.equal(state.requestedAt, START.toISOString());

  state = applyGuardianScreenTimeEmergencyAction(state, {
    action: "approve",
    requestId: REQUEST_ID,
    minutes: 20,
  }, after(1));
  assert.equal(state.status, "approved");
  assert.equal(state.minutes, 20);
  assert.equal(state.approvalExpiresAt, after(11).toISOString());

  state = applyChildScreenTimeEmergencyAction(state, {
    action: "activate",
    requestId: REQUEST_ID,
    sessionEndsAt: "2099-01-01T00:00:00.000Z",
  }, after(2));
  assert.equal(state.status, "active");
  assert.equal(state.sessionEndsAt, after(22).toISOString());

  state = applyChildScreenTimeEmergencyAction(state, {
    action: "complete",
    requestId: REQUEST_ID,
  }, after(10));
  assert.equal(state.status, "completed");
  assert.equal(state.completedAt, after(10).toISOString());
});

test("emergency actions reject illegal transitions and mismatched request IDs", () => {
  const idle = idleScreenTimeEmergency(START);
  throwsCode(() => applyChildScreenTimeEmergencyAction(idle, {
    action: "activate",
    requestId: REQUEST_ID,
  }, START), "emergency_request_mismatch");

  const requested = applyChildScreenTimeEmergencyAction(idle, {
    action: "request",
    requestId: REQUEST_ID,
    reason: "Need access",
    minutes: 15,
  }, START);
  throwsCode(() => applyChildScreenTimeEmergencyAction(requested, {
    action: "complete",
    requestId: REQUEST_ID,
  }, after(1)), "invalid_emergency_transition");
  throwsCode(() => applyGuardianScreenTimeEmergencyAction(requested, {
    action: "approve",
    requestId: "emergency:req:other",
  }, after(1)), "emergency_request_mismatch");
  throwsCode(() => applyChildScreenTimeEmergencyAction(idle, {
    action: "request",
    requestId: "emergency:req:0061",
    reason: "Too long",
    minutes: 61,
  }, START), "invalid_emergency_minutes");

  const denied = applyGuardianScreenTimeEmergencyAction(requested, {
    action: "deny",
    requestId: REQUEST_ID,
  }, after(1));
  assert.equal(denied.status, "denied");
  assert.equal(denied.decidedAt, after(1).toISOString());
});

test("emergency scope rejects cross-family and cross-child access", () => {
  throwsCode(() => assertScreenTimeEmergencyScope({
    actorFamilyId: "family-a",
    childFamilyId: "family-b",
    childProfileId: "child-a",
  }), "screen_time_emergency_access_denied");
  throwsCode(() => assertScreenTimeEmergencyScope({
    actorFamilyId: "family-a",
    childFamilyId: "family-a",
    actorChildProfileId: "child-a",
    childProfileId: "child-b",
  }), "screen_time_emergency_access_denied");
  assert.doesNotThrow(() => assertScreenTimeEmergencyScope({
    actorFamilyId: "family-a",
    childFamilyId: "family-a",
    actorChildProfileId: "child-a",
    childProfileId: "child-a",
  }));
});

test("expired requests and approvals cannot be approved or activated", () => {
  const requested = applyChildScreenTimeEmergencyAction(idleScreenTimeEmergency(START), {
    action: "request",
    requestId: REQUEST_ID,
    reason: "Need access",
    minutes: 15,
  }, START);
  throwsCode(() => applyGuardianScreenTimeEmergencyAction(requested, {
    action: "approve",
    requestId: REQUEST_ID,
  }, after(30)), "emergency_request_expired");

  const approved = applyGuardianScreenTimeEmergencyAction(requested, {
    action: "approve",
    requestId: REQUEST_ID,
  }, after(1));
  throwsCode(() => applyChildScreenTimeEmergencyAction(approved, {
    action: "activate",
    requestId: REQUEST_ID,
  }, after(11)), "emergency_approval_expired");

  const expired = applyChildScreenTimeEmergencyAction(approved, {
    action: "expire",
    requestId: REQUEST_ID,
  }, after(11));
  assert.equal(expired.status, "expired");
  assert.equal(expired.expirationReason, "approval_timeout");

  const requestExpired = applyChildScreenTimeEmergencyAction(requested, {
    action: "expire",
    requestId: REQUEST_ID,
  }, after(30));
  assert.equal(requestExpired.status, "expired");
  assert.equal(requestExpired.expirationReason, "request_timeout");

  const active = applyChildScreenTimeEmergencyAction(approved, {
    action: "activate",
    requestId: REQUEST_ID,
  }, after(2));
  const sessionExpired = applyChildScreenTimeEmergencyAction(active, {
    action: "expire",
    requestId: REQUEST_ID,
  }, after(17));
  assert.equal(sessionExpired.status, "expired");
  assert.equal(sessionExpired.expirationReason, "session_timeout");
});

test("same request ID is idempotent across retries and cannot reopen a completed request", () => {
  const requested = applyChildScreenTimeEmergencyAction(idleScreenTimeEmergency(START), {
    action: "request",
    requestId: REQUEST_ID,
    reason: "Original reason",
    minutes: 10,
  }, START);
  const retried = applyChildScreenTimeEmergencyAction(requested, {
    action: "request",
    requestId: REQUEST_ID,
    reason: "Changed by retry",
    minutes: 60,
  }, after(1));
  assert.deepEqual(retried, requested);

  const approved = applyGuardianScreenTimeEmergencyAction(requested, {
    action: "approve",
    requestId: REQUEST_ID,
  }, after(1));
  const approvedRetry = applyGuardianScreenTimeEmergencyAction(approved, {
    action: "approve",
    requestId: REQUEST_ID,
    minutes: 60,
  }, after(2));
  assert.deepEqual(approvedRetry, approved);

  const active = applyChildScreenTimeEmergencyAction(approved, {
    action: "activate",
    requestId: REQUEST_ID,
  }, after(2));
  const completed = applyChildScreenTimeEmergencyAction(active, {
    action: "complete",
    requestId: REQUEST_ID,
  }, after(3));
  const reopened = applyChildScreenTimeEmergencyAction(completed, {
    action: "request",
    requestId: REQUEST_ID,
    reason: "Retry after completion",
    minutes: 60,
  }, after(4));
  assert.deepEqual(reopened, completed);
});
