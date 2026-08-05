import { updateChildProfile } from "../../../../../src/domain/family/postgres-family-cloud.js";
import { readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../../../_http.js";
import { requireGuardianSession } from "../../../../_family-auth.js";
import { writeFamilyError } from "../../../../_family-errors.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if ((req.method ?? "GET") !== "PUT") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }
  try {
    const context = await requireGuardianSession(req, res);
    if (!context) return;
    const familyId = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    const childProfileId = Array.isArray(req.query?.childId) ? req.query?.childId[0] : req.query?.childId;
    const raw = readJsonBody(req);
    if (!familyId || !childProfileId || !raw || typeof raw !== "object" || Array.isArray(raw)) {
      throw new Error("invalid_json");
    }
    const body = raw as Record<string, unknown>;
    if (typeof body.baseVersion !== "number" || typeof body.clientRef !== "string" || typeof body.displayName !== "string") {
      writeJson(res, 400, { error: "child_fields_required" });
      return;
    }
    const family = await updateChildProfile({
      context,
      familyId,
      childProfileId,
      baseVersion: body.baseVersion,
      clientRef: body.clientRef,
      displayName: body.displayName,
      ...(typeof body.birthYear === "number" ? { birthYear: body.birthYear } : {}),
      preReaderMode: body.preReaderMode === true,
      ...(body.interfaceLanguage === "english" || body.interfaceLanguage === "chinese"
        ? { interfaceLanguage: body.interfaceLanguage } : {}),
      ...(body.contentLanguage === "english" || body.contentLanguage === "chinese" || body.contentLanguage === "bilingual"
        ? { contentLanguage: body.contentLanguage } : {}),
      ...(typeof body.dailyLimitMinutes === "number" ? { dailyLimitMinutes: body.dailyLimitMinutes } : {}),
      ...(body.exchangePolicy && typeof body.exchangePolicy === "object" && !Array.isArray(body.exchangePolicy)
        ? { exchangePolicy: body.exchangePolicy } : {}),
    });
    writeJson(res, 200, { family });
  } catch (error) {
    writeFamilyError(res, error, "child_profile_update_unavailable");
  }
}
