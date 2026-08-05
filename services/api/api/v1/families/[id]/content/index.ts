import { loadGuardianFamilySnapshot, upsertFamilyContent } from "../../../../../src/domain/family/postgres-family-control.js";
import { requireGuardianSession } from "../../../../_family-auth.js";
import { writeFamilyError } from "../../../../_family-errors.js";
import { readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!["GET", "POST"].includes(req.method ?? "GET")) { writeJson(res, 405, { error: "method_not_allowed" }); return; }
  try {
    const context = await requireGuardianSession(req, res); if (!context) return;
    const familyId = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    if (!familyId) throw new Error("invalid_json");
    if ((req.method ?? "GET") === "GET") {
      const snapshot = await loadGuardianFamilySnapshot(context, familyId);
      writeJson(res, 200, { content: snapshot.content, assignments: snapshot.assignments }); return;
    }
    writeJson(res, 200, await upsertFamilyContent({ context, familyId, value: readJsonBody(req) }));
  } catch (error) { writeFamilyError(res, error, "family_content_unavailable"); }
}
