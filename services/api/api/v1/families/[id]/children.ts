import { createChildProfile } from "../../../../src/domain/family/postgres-family-cloud.js";
import { readJsonBody, requirePost, writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";
import { requireGuardianSession } from "../../../_family-auth.js";
import { writeFamilyError } from "../../../_family-errors.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requirePost(req, res)) return;
  try {
    const context = await requireGuardianSession(req, res);
    if (!context) return;
    const id = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    const raw = readJsonBody(req);
    if (!id || !raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("invalid_json");
    const body = raw as Record<string, unknown>;
    if (typeof body.clientRef !== "string" || typeof body.displayName !== "string") {
      writeJson(res, 400, { error: "child_fields_required" });
      return;
    }
    const family = await createChildProfile({
      context, familyId: id, clientRef: body.clientRef, displayName: body.displayName,
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
    writeJson(res, 201, { family });
  } catch (error) {
    writeFamilyError(res, error, "child_profile_unavailable");
  }
}
