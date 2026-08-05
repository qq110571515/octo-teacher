import { withdrawChildDeviceTask } from "../../../../../src/domain/family/postgres-family-cloud.js";
import { legacyMutationRef } from "../../../../../src/domain/family/family-task-sync.js";
import { readJsonBody, requirePost, writeJson, type ApiRequest, type ApiResponse } from "../../../../_http.js";
import { requireChildDeviceSession } from "../../../../_family-auth.js";
import { writeFamilyError } from "../../../../_family-errors.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requirePost(req, res)) return;
  try {
    const context = await requireChildDeviceSession(req, res);
    if (!context) return;
    const taskId = Array.isArray(req.query?.taskId) ? req.query?.taskId[0] : req.query?.taskId;
    const raw = readJsonBody(req);
    if (!taskId || !raw || typeof raw !== "object" || Array.isArray(raw)) {
      writeJson(res, 400, { error: "task_withdraw_fields_required" });
      return;
    }
    const body = raw as Record<string, unknown>;
    writeJson(res, 200, {
      task: await withdrawChildDeviceTask({
        context,
        taskId,
        mutationRef: typeof body.mutationRef === "string"
          ? body.mutationRef
          : legacyMutationRef("child-withdraw-legacy", { taskId }),
        ...(typeof body.expectedVersion === "number" ? { expectedVersion: body.expectedVersion } : {}),
      }),
    });
  } catch (error) {
    writeFamilyError(res, error, "child_task_withdraw_unavailable");
  }
}
