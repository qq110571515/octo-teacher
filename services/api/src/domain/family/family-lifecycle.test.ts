import assert from "node:assert/strict";
import test from "node:test";
import { FamilyCloudError } from "./cloud-types.js";
import { familyDeletionConfirmation, requireFamilyDeletionConfirmation } from "./family-lifecycle.js";

test("family deletion requires the exact public reference", () => {
  const publicRef = "family_0123456789abcdef";
  assert.equal(familyDeletionConfirmation(publicRef), `DELETE ${publicRef}`);
  assert.doesNotThrow(() => requireFamilyDeletionConfirmation(publicRef, `DELETE ${publicRef}`));
  assert.throws(
    () => requireFamilyDeletionConfirmation(publicRef, "DELETE family_other"),
    (error) => error instanceof FamilyCloudError && error.code === "family_deletion_confirmation_invalid",
  );
});
