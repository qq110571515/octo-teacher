import assert from "node:assert/strict";
import test from "node:test";
import { FamilyCloudError } from "./cloud-types.js";
import {
  generatePortalLinkCode,
  normalizePortalLinkCode,
  portalLinkCodeHash,
  resolveAccountIdentityLink,
  resolvePortalLinkClaim,
} from "./family-portal.js";

function errorCode(code: string): (error: unknown) => boolean {
  return (error) => error instanceof FamilyCloudError && error.code === code;
}

test("portal link codes are human-readable while only normalized hashes are stored", () => {
  const code = generatePortalLinkCode();
  assert.match(code, /^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/);
  assert.equal(normalizePortalLinkCode(` ${code.toLowerCase()} `), code.replaceAll("-", ""));
  assert.match(portalLinkCodeHash(code), /^[0-9a-f]{64}$/);
  assert.equal(portalLinkCodeHash(code), portalLinkCodeHash(code.replaceAll("-", "")));
  assert.throws(() => normalizePortalLinkCode("ABCD-EFGH-IJKL"), errorCode("invalid_portal_link_code"));
});

test("portal link claims are one-time and idempotent only for the claiming account", () => {
  const now = new Date("2026-07-15T12:00:00.000Z");
  assert.equal(resolvePortalLinkClaim({
    status: "issued",
    expiresAt: "2026-07-15T12:10:00.000Z",
  }, "account-1", now), "consume");
  assert.equal(resolvePortalLinkClaim({
    status: "consumed",
    expiresAt: "2026-07-15T12:10:00.000Z",
    consumedByAccountId: "account-1",
  }, "account-1", now), "idempotent");
  assert.throws(() => resolvePortalLinkClaim({
    status: "consumed",
    expiresAt: "2026-07-15T12:10:00.000Z",
    consumedByAccountId: "account-1",
  }, "account-2", now), errorCode("portal_link_consumed"));
});

test("portal link claims reject missing, expired, and revoked codes", () => {
  const now = new Date("2026-07-15T12:00:00.000Z");
  assert.throws(() => resolvePortalLinkClaim(undefined, "account-1", now),
    errorCode("portal_link_not_found"));
  assert.throws(() => resolvePortalLinkClaim({
    status: "issued",
    expiresAt: "2026-07-15T12:00:00.000Z",
  }, "account-1", now), errorCode("portal_link_expired"));
  assert.throws(() => resolvePortalLinkClaim({
    status: "revoked",
    expiresAt: "2026-07-15T12:10:00.000Z",
  }, "account-1", now), errorCode("portal_link_unavailable"));
});

test("Apple identity linking is idempotent but never merges two accounts", () => {
  assert.equal(resolveAccountIdentityLink(undefined, "account-1"), "insert");
  assert.equal(resolveAccountIdentityLink("account-1", "account-1"), "refresh");
  assert.throws(
    () => resolveAccountIdentityLink("account-2", "account-1"),
    errorCode("portal_apple_identity_already_linked"),
  );
});
