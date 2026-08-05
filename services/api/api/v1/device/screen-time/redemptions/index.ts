import { reserveScreenTimeRedemption } from "../../../../../src/domain/family/postgres-screen-time-redemption.js";
import { requireChildDeviceSession } from "../../../../_family-auth.js";
import { writeFamilyError } from "../../../../_family-errors.js";
import { readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../../../_http.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if ((req.method ?? "GET") !== "POST") {
    writeJson(res, 405, { error: "method_not_allowed" });
    return;
  }
  try {
    const context = await requireChildDeviceSession(req, res);
    if (!context) return;
    writeJson(res, 200, await reserveScreenTimeRedemption({
      context,
      receipt: readJsonBody(req),
    }));
  } catch (error) {
    writeFamilyError(res, error, "screen_time_redemption_reserve_unavailable");
  }
}
