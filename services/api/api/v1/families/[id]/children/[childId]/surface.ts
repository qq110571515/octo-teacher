import { loadGuardianChildSurface } from "../../../../../../src/domain/family/postgres-family-control.js";
import { requireGuardianSession } from "../../../../../_family-auth.js";
import { writeFamilyError } from "../../../../../_family-errors.js";
import { requireGet, writeJson, type ApiRequest, type ApiResponse } from "../../../../../_http.js";

function first(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requireGet(req, res)) return;
  try {
    const context = await requireGuardianSession(req, res);
    if (!context) return;
    const familyId = first(req.query?.id);
    const childId = first(req.query?.childId);
    if (!familyId || !childId) {
      writeJson(res, 400, { error: "family_and_child_required" });
      return;
    }
    writeJson(res, 200, { surface: await loadGuardianChildSurface(context, familyId, childId) });
  } catch (error) {
    writeFamilyError(res, error, "child_surface_unavailable");
  }
}
