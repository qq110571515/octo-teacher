import { authenticateGuardianToken, authenticateChildDeviceToken } from "../src/domain/family/postgres-family-cloud.js";
import type { ChildDeviceSessionContext, GuardianSessionContext } from "../src/domain/family/cloud-types.js";
import { childDeviceProtocolDecision } from "../src/domain/family/child-device-protocol.js";
import { bearerToken, requestHeader, writeJson, type ApiRequest, type ApiResponse } from "./_http.js";

export async function requireGuardianSession(
  req: ApiRequest,
  res: ApiResponse,
): Promise<GuardianSessionContext | undefined> {
  const context = await authenticateGuardianToken(bearerToken(req));
  if (!context) {
    res.setHeader("www-authenticate", "Bearer");
    writeJson(res, 401, { error: "guardian_session_required" });
    return undefined;
  }
  return context;
}

export async function optionalGuardianSession(req: ApiRequest): Promise<GuardianSessionContext | undefined> {
  return authenticateGuardianToken(bearerToken(req));
}

export async function requireChildDeviceSession(
  req: ApiRequest,
  res: ApiResponse,
): Promise<ChildDeviceSessionContext | undefined> {
  const context = await authenticateChildDeviceToken(bearerToken(req));
  if (!context) {
    res.setHeader("www-authenticate", "Bearer");
    writeJson(res, 401, { error: "child_device_session_required" });
    return undefined;
  }
  const decision = childDeviceProtocolDecision({
    clientGeneration: requestHeader(req, "x-octo-child-protocol"),
    bindingGeneration: context.protocolGeneration,
  });
  if (decision === "client_update_required") {
    writeJson(res, 426, { error: "child_device_update_required" });
    return undefined;
  }
  if (decision === "client_protocol_unsupported") {
    writeJson(res, 409, { error: "child_device_protocol_unsupported" });
    return undefined;
  }
  if (decision === "device_rebind_required") {
    writeJson(res, 409, { error: "child_device_rebind_required" });
    return undefined;
  }
  return context;
}
