import assert from "node:assert/strict";
import test from "node:test";
import { FamilyCloudError } from "../family/cloud-types.js";
import { normalizeEmailDeviceCode, resolveEmailDeviceExchange } from "./email-device-authorization.js";

function errorCode(code: string): (error: unknown) => boolean {
  return (error) => error instanceof FamilyCloudError && error.code === code;
}

test("email device codes normalize without ambiguous characters", () => {
  assert.equal(normalizeEmailDeviceCode(" abcd-2345 "), "ABCD2345");
  assert.throws(() => normalizeEmailDeviceCode("ABCI-2345"), errorCode("invalid_email_device_code"));
});

test("email device exchange waits for approval then completes exactly once", () => {
  const now = new Date("2026-07-16T12:00:00.000Z");
  assert.equal(resolveEmailDeviceExchange({
    status: "pending", expiresAt: "2026-07-16T12:10:00.000Z",
  }, now), "pending");
  assert.equal(resolveEmailDeviceExchange({
    status: "approved", accountId: "account-1", expiresAt: "2026-07-16T12:10:00.000Z",
  }, now), "exchange");
  assert.throws(() => resolveEmailDeviceExchange({
    status: "consumed", accountId: "account-1", expiresAt: "2026-07-16T12:10:00.000Z",
  }, now), errorCode("email_device_code_unavailable"));
  assert.throws(() => resolveEmailDeviceExchange({
    status: "approved", accountId: "account-1", expiresAt: "2026-07-16T12:00:00.000Z",
  }, now), errorCode("email_device_code_expired"));
});
