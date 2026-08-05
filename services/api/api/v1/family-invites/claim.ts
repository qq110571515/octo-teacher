import { claimFamilyInvite } from "../../../src/domain/family/postgres-family-cloud.js";
import { optionalGuardianSession } from "../../_family-auth.js";
import { writeFamilyError } from "../../_family-errors.js";
import { readJsonBody, requirePost, writeJson, type ApiRequest, type ApiResponse } from "../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requirePost(req, res)) return;
  try {
    const raw = readJsonBody(req);
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("invalid_json");
    const body = raw as Record<string, unknown>;
    if (typeof body.publicRef !== "string" || typeof body.secret !== "string" ||
        typeof body.devicePublicRef !== "string" || typeof body.deviceName !== "string") {
      writeJson(res, 400, { error: "invite_claim_fields_required" });
      return;
    }
    const result = await claimFamilyInvite({
      publicRef: body.publicRef,
      secret: body.secret,
      devicePublicRef: body.devicePublicRef,
      deviceName: body.deviceName,
      guardianContext: await optionalGuardianSession(req),
      ...(typeof body.consentVersion === "string" ? { consentVersion: body.consentVersion } : {}),
      familySyncAccepted: body.familySyncAccepted === true,
      childTaskSyncAccepted: body.childTaskSyncAccepted === true,
      protocolGeneration: body.protocolGeneration,
    });
    writeJson(res, 200, result);
  } catch (error) {
    writeFamilyError(res, error, "invite_claim_unavailable");
  }
}
