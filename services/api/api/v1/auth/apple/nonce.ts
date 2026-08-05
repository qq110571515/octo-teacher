import { issueAppleAuthNonce } from "../../../../src/domain/family/postgres-family-cloud.js";
import { requestHeader, requirePost, writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";
import { writeFamilyError } from "../../../_family-errors.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requirePost(req, res)) return;
  try {
    const deviceRef = requestHeader(req, "x-octoteacher-device-ref");
    if (!deviceRef) {
      writeJson(res, 400, { error: "device_ref_required" });
      return;
    }
    writeJson(res, 200, await issueAppleAuthNonce(deviceRef));
  } catch (error) {
    writeFamilyError(res, error, "apple_nonce_unavailable");
  }
}
