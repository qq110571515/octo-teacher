import { claimFamilyPortalLink } from "../../../../src/domain/family/postgres-family-portal.js";
import { FamilyCloudError } from "../../../../src/domain/family/cloud-types.js";
import { requirePlatformIdentity } from "../../../_account-auth.js";
import { writeFamilyError } from "../../../_family-errors.js";
import { applyPortalCors, readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (applyPortalCors(req, res)) return;
  if ((req.method ?? "GET") !== "POST") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }
  try {
    const identity = await requirePlatformIdentity(req, res);
    if (!identity) return;
    const body = readJsonBody(req);
    if (!body || typeof body !== "object" || Array.isArray(body) ||
        Object.keys(body).some((key) => key !== "code")) {
      throw new FamilyCloudError("invalid_portal_link_request");
    }
    const family = await claimFamilyPortalLink(identity, (body as { code?: unknown }).code);
    writeJson(res, 200, { family });
  } catch (error) {
    writeFamilyError(res, error, "family_portal_link_claim_unavailable");
  }
}
