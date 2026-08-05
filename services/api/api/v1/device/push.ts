import { registerChildDevicePush } from "../../../src/domain/family/postgres-family-cloud.js";
import { requireChildDeviceSession } from "../../_family-auth.js";
import { writeFamilyError } from "../../_family-errors.js";
import { readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if ((req.method ?? "GET") !== "PUT") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }
  try {
    const context = await requireChildDeviceSession(req, res);
    if (!context) return;
    const body = readJsonBody(req);
    const child = await registerChildDevicePush({ context, registration: body });
    writeJson(res, 200, { child });
  } catch (error) {
    writeFamilyError(res, error, "push_registration_unavailable");
  }
}
