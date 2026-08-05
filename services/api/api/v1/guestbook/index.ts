import {
  GuestbookError,
  hashGuestbookIp,
  parseGuestbookSubmission,
  verifyGuestbookChallenge,
} from "../../../src/domain/guestbook/guestbook.js";
import {
  createGuestbookMessage,
  listGuestbookMessages,
} from "../../../src/domain/guestbook/postgres-guestbook.js";
import { applyPortalCors, readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../_http.js";
import { guestbookRequestIp, guestbookSecret, requireGuestbookPortalOrigin } from "../../_guestbook.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (applyPortalCors(req, res)) return;
  const method = req.method ?? "GET";
  try {
    if (method === "GET") {
      writeJson(res, 200, { messages: await listGuestbookMessages() });
      return;
    }
    if (method === "POST") {
      if (!requireGuestbookPortalOrigin(req, res)) return;
      const secret = guestbookSecret();
      const ipAddress = guestbookRequestIp(req);
      const submission = parseGuestbookSubmission(readJsonBody(req));
      verifyGuestbookChallenge({ secret, ipAddress, submission });
      const message = await createGuestbookMessage({
        displayName: submission.displayName,
        message: submission.message,
        ipHash: hashGuestbookIp(secret, ipAddress),
      });
      writeJson(res, 201, { message });
      return;
    }
    writeJson(res, 405, { error: "method_not_allowed" });
  } catch (error) {
    if (error instanceof GuestbookError) {
      const status = error.code === "guestbook_rate_limited" ? 429 : error.code === "guestbook_duplicate" ? 409 : 400;
      writeJson(res, status, { error: error.code });
      return;
    }
    if (error instanceof Error && error.message === "invalid_json") {
      writeJson(res, 400, { error: "invalid_json" });
      return;
    }
    writeJson(res, 503, { error: "guestbook_unavailable" });
  }
}
