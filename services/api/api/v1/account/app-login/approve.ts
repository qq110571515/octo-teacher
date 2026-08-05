import { approveEmailDeviceAuthorization } from "../../../../src/domain/accounts/email-device-authorization.js";
import { loadActivePlatformAccountIdentity } from "../../../../src/domain/accounts/postgres-platform-accounts.js";
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
    const account = await loadActivePlatformAccountIdentity(identity);
    if (!account) {
      writeJson(res, 403, { error: "portal_account_not_active" });
      return;
    }
    const raw = readJsonBody(req);
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("invalid_json");
    await approveEmailDeviceAuthorization((raw as Record<string, unknown>).code, account.id);
    writeJson(res, 200, { approved: true });
  } catch (error) {
    writeFamilyError(res, error, "email_device_approval_unavailable");
  }
}
