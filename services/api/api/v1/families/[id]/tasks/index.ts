import {
  listGuardianTaskChanges,
  listGuardianTaskSnapshot,
  syncGuardianTasks,
} from "../../../../../src/domain/family/postgres-family-cloud.js";
import { legacyMutationRef } from "../../../../../src/domain/family/family-task-sync.js";
import { readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../../../_http.js";
import { requireGuardianSession } from "../../../../_family-auth.js";
import { writeFamilyError } from "../../../../_family-errors.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  try {
    const context = await requireGuardianSession(req, res);
    if (!context) return;
    const familyId = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    if (!familyId) {
      writeJson(res, 400, { error: "family_id_required" });
      return;
    }
    if ((req.method ?? "GET") === "GET") {
      const snapshot = Array.isArray(req.query?.snapshot) ? req.query?.snapshot[0] : req.query?.snapshot;
      writeJson(
        res,
        200,
        snapshot === "1"
          ? await listGuardianTaskSnapshot(context, familyId)
          : await listGuardianTaskChanges(context, familyId, req.query?.cursor),
      );
      return;
    }
    if (req.method === "POST") {
      const raw = readJsonBody(req);
      if (!raw || typeof raw !== "object" || Array.isArray(raw) || !Array.isArray((raw as Record<string, unknown>).tasks)) {
        writeJson(res, 400, { error: "tasks_required" });
        return;
      }
      const body = raw as {
        tasks: Parameters<typeof syncGuardianTasks>[0]["tasks"];
        mutationRef?: string;
        cursor?: number;
      };
      const mutationRef = body.mutationRef ?? legacyMutationRef("guardian-legacy", body.tasks);
      await syncGuardianTasks({ context, familyId, mutationRef, tasks: body.tasks });
      writeJson(res, 200, await listGuardianTaskChanges(context, familyId, body.cursor));
      return;
    }
    writeJson(res, 405, { error: "method_not_allowed" });
  } catch (error) {
    writeFamilyError(res, error, "family_tasks_unavailable");
  }
}
