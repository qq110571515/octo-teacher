import { loadCurrentFamily, revokeGuardianSession } from "../../../src/domain/family/postgres-family-cloud.js";
import { writeJson, type ApiRequest, type ApiResponse } from "../../_http.js";
import { requireGuardianSession } from "../../_family-auth.js";
import { writeFamilyError } from "../../_family-errors.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  try {
    const context = await requireGuardianSession(req, res);
    if (!context) return;
    if ((req.method ?? "GET") === "GET") {
      writeJson(res, 200, { guardian: { id: context.guardianId, displayName: context.displayName }, family: await loadCurrentFamily(context) });
      return;
    }
    if (req.method === "DELETE") {
      await revokeGuardianSession(context);
      writeJson(res, 200, { revoked: true });
      return;
    }
    writeJson(res, 405, { error: "method_not_allowed" });
  } catch (error) {
    writeFamilyError(res, error, "guardian_session_unavailable");
  }
}
