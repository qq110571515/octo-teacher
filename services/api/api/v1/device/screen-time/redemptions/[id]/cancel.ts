import { cancelScreenTimeRedemption } from "../../../../../../src/domain/family/postgres-screen-time-redemption.js";
import { requireChildDeviceSession } from "../../../../../_family-auth.js";
import { writeFamilyError } from "../../../../../_family-errors.js";
import { writeJson, type ApiRequest, type ApiResponse } from "../../../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if ((req.method ?? "GET") !== "POST") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }
  try {
    const context = await requireChildDeviceSession(req, res);
    if (!context) return;
    const redemptionId = Array.isArray(req.query?.id) ? req.query?.id[0] : req.query?.id;
    if (!redemptionId) {
      writeJson(res, 400, { error: "invalid_screen_time_redemption_id" });
      return;
    }
    writeJson(res, 200, await cancelScreenTimeRedemption({ context, redemptionId }));
  } catch (error) {
    writeFamilyError(res, error, "screen_time_redemption_cancel_unavailable");
  }
}
