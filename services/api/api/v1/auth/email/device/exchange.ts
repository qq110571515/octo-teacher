import { exchangeEmailDeviceAuthorization } from "../../../../../src/domain/accounts/email-device-authorization.js";
import { writeFamilyError } from "../../../../_family-errors.js";
import { readJsonBody, requirePost, writeJson, type ApiRequest, type ApiResponse } from "../../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requirePost(req, res)) return;
  try {
    const raw = readJsonBody(req);
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("invalid_json");
    const body = raw as Record<string, unknown>;
    const result = await exchangeEmailDeviceAuthorization({
      requestToken: body.requestToken,
      devicePublicRef: body.devicePublicRef,
      consentVersion: body.consentVersion,
      familySyncAccepted: body.familySyncAccepted,
      childTaskSyncAccepted: body.childTaskSyncAccepted,
    });
    writeJson(res, result.status === "pending" ? 202 : 201, result);
  } catch (error) {
    writeFamilyError(res, error, "email_device_session_unavailable");
  }
}
