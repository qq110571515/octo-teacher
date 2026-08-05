import type { GuardianSessionContext } from "../../../../../src/domain/family/cloud-types.js";
import { updateFamilyScreenTimeControl } from "../../../../../src/domain/family/postgres-family-cloud.js";
import { loadLinkedGuardian } from "../../../../../src/domain/family/postgres-family-portal.js";
import { requirePlatformIdentity } from "../../../../_account-auth.js";
import { writeFamilyError } from "../../../../_family-errors.js";
import {
  applyPortalCors,
  readJsonBody,
  writeJson,
  type ApiRequest,
  type ApiResponse,
} from "../../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (applyPortalCors(req, res)) return;
  if ((req.method ?? "GET") !== "PUT") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }
  try {
    const identity = await requirePlatformIdentity(req, res);
    if (!identity) return;
    const raw = readJsonBody(req);
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      writeJson(res, 400, { error: "invalid_json" });
      return;
    }
    const body = raw as Record<string, unknown>;
    if (typeof body.childProfileId !== "string") {
      writeJson(res, 400, { error: "child_profile_required" });
      return;
    }
    const linked = await loadLinkedGuardian(identity);
    const context: GuardianSessionContext = {
      sessionId: "portal-account",
      guardianId: linked.guardianId,
      devicePublicRef: "portal-account",
    };
    await updateFamilyScreenTimeControl({
      context,
      familyId: linked.familyId,
      childProfileId: body.childProfileId,
      control: body,
    });
    writeJson(res, 200, { ok: true });
  } catch (error) {
    writeFamilyError(res, error, "screen_time_control_unavailable");
  }
}
