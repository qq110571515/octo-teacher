import { deleteFamilyData } from "../../../../src/domain/family/postgres-family-cloud.js";
import { loadGuardianFamilySnapshot, renameFamily } from "../../../../src/domain/family/postgres-family-control.js";
import { readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";
import { requireGuardianSession } from "../../../_family-auth.js";
import { writeFamilyError } from "../../../_family-errors.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!["GET", "PATCH", "DELETE"].includes(req.method ?? "GET")) {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }
  try {
    const context = await requireGuardianSession(req, res);
    if (!context) return;
    const id = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    if (!id) throw new Error("invalid_json");
    if ((req.method ?? "GET") === "GET") {
      writeJson(res, 200, { snapshot: await loadGuardianFamilySnapshot(context, id) });
      return;
    }
    const raw = readJsonBody(req);
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("invalid_json");
    if (req.method === "PATCH") {
      const body = raw as Record<string, unknown>;
      writeJson(res, 200, await renameFamily({ context, familyId: id,
        displayName: body.displayName, baseVersion: body.baseVersion }));
      return;
    }
    const result = await deleteFamilyData({
      context,
      familyId: id,
      confirmation: (raw as Record<string, unknown>).confirmation,
    });
    writeJson(res, 200, { deleted: true, ...result });
  } catch (error) {
    writeFamilyError(res, error, "family_delete_unavailable");
  }
}
