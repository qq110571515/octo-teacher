import assert from "node:assert/strict";
import test from "node:test";
import { FamilyCloudError } from "./cloud-types.js";
import { requireCompatibleGuardianFamilies } from "./guardian-identity.js";

function errorCode(code: string): (error: unknown) => boolean {
  return (error) => error instanceof FamilyCloudError && error.code === code;
}

test("guardian identity aliases may collapse only inside one active family", () => {
  assert.doesNotThrow(() => requireCompatibleGuardianFamilies([], []));
  assert.doesNotThrow(() => requireCompatibleGuardianFamilies(["family-a"], []));
  assert.doesNotThrow(() => requireCompatibleGuardianFamilies(["family-a"], ["family-a"]));
  assert.doesNotThrow(() => requireCompatibleGuardianFamilies([], ["family-a"], "family-a"));
});

test("guardian identity aliases never guess across active families", () => {
  assert.throws(
    () => requireCompatibleGuardianFamilies(["family-a"], ["family-b"]),
    errorCode("guardian_identity_family_conflict"),
  );
  assert.throws(
    () => requireCompatibleGuardianFamilies([], ["family-b"], "family-a"),
    errorCode("guardian_identity_family_conflict"),
  );
});
