import {
  listChildDeviceTaskChanges,
  listChildDeviceTaskSnapshot,
} from "../../../../src/domain/family/postgres-family-cloud.js";
import { writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";
import { requireChildDeviceSession } from "../../../_family-auth.js";
import { writeFamilyError } from "../../../_family-errors.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if ((req.method ?? "GET") !== "GET") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }
  try {
    const context = await requireChildDeviceSession(req, res);
    if (!context) return;
    const snapshot = Array.isArray(req.query?.snapshot) ? req.query?.snapshot[0] : req.query?.snapshot;
    writeJson(
      res,
      200,
      snapshot === "1"
        ? await listChildDeviceTaskSnapshot(context)
        : await listChildDeviceTaskChanges(context, req.query?.cursor),
    );
  } catch (error) {
    writeFamilyError(res, error, "child_tasks_unavailable");
  }
}
