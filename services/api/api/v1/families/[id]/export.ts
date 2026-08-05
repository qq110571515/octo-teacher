import { exportFamilyData } from "../../../../src/domain/family/postgres-family-cloud.js";
import { requireGet, writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";
import { requireGuardianSession } from "../../../_family-auth.js";
import { writeFamilyError } from "../../../_family-errors.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requireGet(req, res)) return;
  try {
    const context = await requireGuardianSession(req, res);
    if (!context) return;
    const id = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    if (!id) throw new Error("invalid_json");
    writeJson(res, 200, { export: await exportFamilyData(context, id) });
  } catch (error) {
    writeFamilyError(res, error, "family_export_unavailable");
  }
}
