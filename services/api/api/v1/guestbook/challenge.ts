import { createGuestbookChallenge } from "../../../src/domain/guestbook/guestbook.js";
import { applyPortalCors, requireGet, writeJson, type ApiRequest, type ApiResponse } from "../../_http.js";
import { guestbookRequestIp, guestbookSecret, requireGuestbookPortalOrigin } from "../../_guestbook.js";

export default function handler(req: ApiRequest, res: ApiResponse): void {
  if (applyPortalCors(req, res)) return;
  if (!requireGet(req, res) || !requireGuestbookPortalOrigin(req, res)) return;
  try {
    const challenge = createGuestbookChallenge(guestbookSecret(), guestbookRequestIp(req));
    writeJson(res, 200, { challenge });
  } catch {
    writeJson(res, 503, { error: "guestbook_unavailable" });
  }
}
