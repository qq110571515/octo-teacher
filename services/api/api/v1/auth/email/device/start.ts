import { startEmailDeviceAuthorization } from "../../../../../src/domain/accounts/email-device-authorization.js";
import { writeFamilyError } from "../../../../_family-errors.js";
import { readJsonBody, requirePost, writeJson, type ApiRequest, type ApiResponse } from "../../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requirePost(req, res)) return;
  try {
    const raw = readJsonBody(req);
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("invalid_json");
    const body = raw as Record<string, unknown>;
    const authorization = await startEmailDeviceAuthorization({
      devicePublicRef: body.devicePublicRef,
      deviceName: body.deviceName,
    });
    writeJson(res, 201, authorization);
  } catch (error) {
    writeFamilyError(res, error, "email_device_authorization_unavailable");
  }
}
