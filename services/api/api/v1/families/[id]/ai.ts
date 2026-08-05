import { configureFamilyAIRelay } from "../../../../src/domain/family/family-ai-relay.js";
import { requireGuardianSession } from "../../../_family-auth.js";
import { writeFamilyError } from "../../../_family-errors.js";
import { readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if ((req.method ?? "GET") !== "PUT") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }
  try {
    const context = await requireGuardianSession(req, res);
    if (!context) return;
    const familyId = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    if (!familyId) {
      writeJson(res, 400, { error: "family_id_required" });
      return;
    }
    const ai = await configureFamilyAIRelay(context, familyId, readJsonBody(req));
    writeJson(res, 200, { ai });
  } catch (error) {
    writeFamilyError(res, error, "family_ai_configuration_unavailable");
  }
}
