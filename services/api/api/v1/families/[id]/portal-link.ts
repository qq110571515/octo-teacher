import { issueFamilyPortalLink } from "../../../../src/domain/family/postgres-family-portal.js";
import { requireGuardianSession } from "../../../_family-auth.js";
import { writeFamilyError } from "../../../_family-errors.js";
import { writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if ((req.method ?? "GET") !== "POST") {
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
    writeJson(res, 200, await issueFamilyPortalLink({ context, familyId }));
  } catch (error) {
    writeFamilyError(res, error, "family_portal_link_unavailable");
  }
}
