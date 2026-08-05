import { familyAICapabilitiesForChild } from "../../../../src/domain/family/family-ai-relay.js";
import { requireChildDeviceSession } from "../../../_family-auth.js";
import { writeFamilyError } from "../../../_family-errors.js";
import { writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if ((req.method ?? "GET") !== "GET") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }
  try {
    const context = await requireChildDeviceSession(req, res);
    if (!context) return;
    writeJson(res, 200, { ai: await familyAICapabilitiesForChild(context) });
  } catch (error) {
    writeFamilyError(res, error, "family_ai_status_unavailable");
  }
}
