import { FamilyCloudError } from "./cloud-types.js";

export type ChildDeviceProfileUpdate = {
  interfaceLanguage: "chinese" | "english";
};

export function normalizeChildDeviceProfileUpdate(value: unknown): ChildDeviceProfileUpdate {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new FamilyCloudError("invalid_child_device_profile_update");
  }

  const body = value as Record<string, unknown>;
  const keys = Object.keys(body);
  if (keys.length !== 1 || keys[0] !== "interfaceLanguage") {
    throw new FamilyCloudError("child_device_profile_fields_forbidden");
  }

  if (body.interfaceLanguage !== "chinese" && body.interfaceLanguage !== "english") {
    throw new FamilyCloudError("invalid_child_interface_language");
  }

  return { interfaceLanguage: body.interfaceLanguage };
}
