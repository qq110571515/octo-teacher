import { updateChildScreenTimeEmergency } from "../../../../src/domain/family/postgres-family-cloud.js";
import { requireChildDeviceSession } from "../../../_family-auth.js";
import { writeFamilyError } from "../../../_family-errors.js";
import { readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if ((req.method ?? "GET") !== "PUT") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }
  try {
    const context = await requireChildDeviceSession(req, res);
    if (!context) return;
    const body = readJsonBody(req);
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      writeJson(res, 400, { error: "invalid_json" });
      return;
    }
    const child = await updateChildScreenTimeEmergency({ context, emergency: body });
    writeJson(res, 200, { child });
  } catch (error) {
    writeFamilyError(res, error, "screen_time_emergency_unavailable");
  }
}
