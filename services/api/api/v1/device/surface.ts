import { loadChildDeviceSurface } from "../../../src/domain/family/postgres-family-control.js";
import { requireChildDeviceSession } from "../../_family-auth.js";
import { writeFamilyError } from "../../_family-errors.js";
import { requireGet, writeJson, type ApiRequest, type ApiResponse } from "../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requireGet(req, res)) return;
  try {
    const context = await requireChildDeviceSession(req, res);
    if (!context) return;
    writeJson(res, 200, { surface: await loadChildDeviceSurface(context) });
  } catch (error) {
    writeFamilyError(res, error, "child_surface_unavailable");
  }
}
