import { normalizeChildDeviceProfileUpdate } from "../../../src/domain/family/child-device-profile.js";
import {
  loadChildDeviceProfile,
  updateChildDeviceInterfaceLanguage,
} from "../../../src/domain/family/postgres-family-cloud.js";
import { requireChildDeviceSession } from "../../_family-auth.js";
import { writeFamilyError } from "../../_family-errors.js";
import { readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../_http.js";

export type ChildDeviceProfileHandlerDependencies = {
  requireSession: typeof requireChildDeviceSession;
  loadProfile: typeof loadChildDeviceProfile;
  updateInterfaceLanguage: typeof updateChildDeviceInterfaceLanguage;
};

const defaultDependencies: ChildDeviceProfileHandlerDependencies = {
  requireSession: requireChildDeviceSession,
  loadProfile: loadChildDeviceProfile,
  updateInterfaceLanguage: updateChildDeviceInterfaceLanguage,
};

export async function handleChildDeviceProfile(
  req: ApiRequest,
  res: ApiResponse,
  dependencies: ChildDeviceProfileHandlerDependencies = defaultDependencies,
): Promise<void> {
  const method = req.method ?? "GET";
  if (method !== "GET" && method !== "PUT") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }
  try {
    const context = await dependencies.requireSession(req, res);
    if (!context) return;
    const child = method === "PUT"
      ? await dependencies.updateInterfaceLanguage(
        context,
        normalizeChildDeviceProfileUpdate(readJsonBody(req)).interfaceLanguage,
      )
      : await dependencies.loadProfile(context);
    writeJson(res, 200, { child });
  } catch (error) {
    writeFamilyError(res, error, "child_profile_unavailable");
  }
}

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  await handleChildDeviceProfile(req, res);
}
