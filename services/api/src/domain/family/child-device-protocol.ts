import { FamilyCloudError } from "./cloud-types.js";

export const CURRENT_CHILD_DEVICE_PROTOCOL_GENERATION = 2;

export type ChildDeviceProtocolDecision =
  | "compatible"
  | "client_update_required"
  | "client_protocol_unsupported"
  | "device_rebind_required";

export function parseChildDeviceProtocolGeneration(value: unknown): number | undefined {
  const parsed = typeof value === "number"
    ? value
    : typeof value === "string" && /^\d+$/.test(value.trim())
      ? Number(value)
      : Number.NaN;
  return Number.isSafeInteger(parsed) && parsed > 0 && parsed <= 32_767
    ? parsed
    : undefined;
}

export function childDeviceProtocolDecision(input: {
  clientGeneration: unknown;
  bindingGeneration: number;
}): ChildDeviceProtocolDecision {
  const clientGeneration = parseChildDeviceProtocolGeneration(input.clientGeneration);
  if (clientGeneration === undefined || clientGeneration < CURRENT_CHILD_DEVICE_PROTOCOL_GENERATION) {
    return "client_update_required";
  }
  if (clientGeneration > CURRENT_CHILD_DEVICE_PROTOCOL_GENERATION) {
    return "client_protocol_unsupported";
  }
  return input.bindingGeneration === CURRENT_CHILD_DEVICE_PROTOCOL_GENERATION
    ? "compatible"
    : "device_rebind_required";
}

export function requireCurrentChildDeviceProtocol(value: unknown): number {
  const decision = childDeviceProtocolDecision({
    clientGeneration: value,
    bindingGeneration: CURRENT_CHILD_DEVICE_PROTOCOL_GENERATION,
  });
  if (decision === "client_update_required") {
    throw new FamilyCloudError("child_device_update_required");
  }
  if (decision !== "compatible") {
    throw new FamilyCloudError("child_device_protocol_unsupported");
  }
  return CURRENT_CHILD_DEVICE_PROTOCOL_GENERATION;
}
