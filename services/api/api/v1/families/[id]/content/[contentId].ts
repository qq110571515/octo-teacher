import { archiveFamilyContent } from "../../../../../src/domain/family/postgres-family-control.js";
import { requireGuardianSession } from "../../../../_family-auth.js";
import { writeFamilyError } from "../../../../_family-errors.js";
import { readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (req.method !== "DELETE") { writeJson(res, 405, { error: "method_not_allowed" }); return; }
  try {
    const context = await requireGuardianSession(req, res); if (!context) return;
    const familyId = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    const contentId = Array.isArray(req.query?.contentId) ? req.query?.contentId[0] : req.query?.contentId;
    const body = readJsonBody(req) as Record<string, unknown> | undefined;
    if (!familyId || !contentId || !body || typeof body !== "object" || Array.isArray(body)) throw new Error("invalid_json");
    writeJson(res, 200, await archiveFamilyContent({ context, familyId, contentId,
      mutationRef: body.mutationRef, baseVersion: body.baseVersion }));
  } catch (error) { writeFamilyError(res, error, "family_content_archive_unavailable"); }
}
