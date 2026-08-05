import { issueFamilyInvite } from "../../../../src/domain/family/postgres-family-cloud.js";
import { readJsonBody, requirePost, writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";
import { requireGuardianSession } from "../../../_family-auth.js";
import { writeFamilyError } from "../../../_family-errors.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requirePost(req, res)) return;
  try {
    const context = await requireGuardianSession(req, res);
    if (!context) return;
    const id = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    const raw = readJsonBody(req);
    if (!id || !raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("invalid_json");
    const body = raw as Record<string, unknown>;
    if (body.kind !== "guardian" && body.kind !== "child_device") {
      writeJson(res, 400, { error: "invalid_invite_kind" });
      return;
    }
    const invite = await issueFamilyInvite({
      context, familyId: id, kind: body.kind,
      ...(typeof body.childProfileId === "string" ? { childProfileId: body.childProfileId } : {}),
    });
    writeJson(res, 201, { invite });
  } catch (error) {
    writeFamilyError(res, error, "family_invite_unavailable");
  }
}
