import { FamilyCloudError } from "../../../../../src/domain/family/cloud-types.js";
import { recordGuardianActivityEvents } from "../../../../../src/domain/family/postgres-family-activity.js";
import { requireGuardianSession } from "../../../../_family-auth.js";
import { writeFamilyError } from "../../../../_family-errors.js";
import { readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if ((req.method ?? "GET") !== "POST") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }
  try {
    const context = await requireGuardianSession(req, res);
    if (!context) return;
    const familyId = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    if (!familyId) {
      writeJson(res, 400, { error: "family_id_required" });
      return;
    }
    const body = readJsonBody(req);
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new FamilyCloudError("invalid_activity_payload");
    }
    const raw = body as Record<string, unknown>;
    if (Object.keys(raw).some((key) => !["childProfileId", "event", "events"].includes(key))) {
      throw new FamilyCloudError("forbidden_activity_field");
    }
    if (typeof raw.childProfileId !== "string" || !raw.childProfileId.trim()) {
      throw new FamilyCloudError("invalid_child_profile_id");
    }
    const hasEvent = Object.hasOwn(raw, "event");
    const hasEvents = Object.hasOwn(raw, "events");
    if (hasEvent === hasEvents) throw new FamilyCloudError("invalid_activity_payload");
    const value = hasEvent ? { event: raw.event } : { events: raw.events };
    writeJson(res, 200, await recordGuardianActivityEvents({
      context,
      familyId,
      childProfileId: raw.childProfileId.trim(),
      value,
    }));
  } catch (error) {
    writeFamilyError(res, error, "family_activity_unavailable");
  }
}
