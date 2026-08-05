import { updateFamilyScreenTimePolicy } from "../../../../src/domain/family/postgres-family-cloud.js";
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
    const raw = readJsonBody(req);
    if (!familyId || !raw || typeof raw !== "object" || Array.isArray(raw)) {
      writeJson(res, 400, { error: "invalid_json" });
      return;
    }
    const body = raw as Record<string, unknown>;
    if (typeof body.childProfileId !== "string") {
      writeJson(res, 400, { error: "child_profile_required" });
      return;
    }
    const family = await updateFamilyScreenTimePolicy({
      context,
      familyId,
      childProfileId: body.childProfileId,
      policy: body.policy,
    });
    writeJson(res, 200, { family });
  } catch (error) {
    writeFamilyError(res, error, "screen_time_policy_unavailable");
  }
}
