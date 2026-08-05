import assert from "node:assert/strict";
import test from "node:test";
import { FamilyCloudError } from "./cloud-types.js";
import { normalizeChildDeviceProfileUpdate } from "./child-device-profile.js";

function rejectsWithCode(value: unknown, code: string): void {
  assert.throws(
    () => normalizeChildDeviceProfileUpdate(value),
    (error) => error instanceof FamilyCloudError && error.code === code,
  );
}

test("child device profile update accepts only supported interface languages", () => {
  assert.deepEqual(normalizeChildDeviceProfileUpdate({ interfaceLanguage: "chinese" }), {
    interfaceLanguage: "chinese",
  });
  assert.deepEqual(normalizeChildDeviceProfileUpdate({ interfaceLanguage: "english" }), {
    interfaceLanguage: "english",
  });
});

test("child device profile update rejects missing or unsupported interface languages", () => {
  rejectsWithCode(null, "invalid_child_device_profile_update");
  rejectsWithCode([], "invalid_child_device_profile_update");
  rejectsWithCode({}, "child_device_profile_fields_forbidden");
  rejectsWithCode({ interfaceLanguage: "spanish" }, "invalid_child_interface_language");
});

test("child device profile update rejects every field other than interfaceLanguage", () => {
  rejectsWithCode(
    { interfaceLanguage: "english", displayName: "Changed by child" },
    "child_device_profile_fields_forbidden",
  );
  rejectsWithCode(
    { interfaceLanguage: "english", dailyLimitMinutes: 720 },
    "child_device_profile_fields_forbidden",
  );
  rejectsWithCode(
    { contentLanguage: "english" },
    "child_device_profile_fields_forbidden",
  );
});
