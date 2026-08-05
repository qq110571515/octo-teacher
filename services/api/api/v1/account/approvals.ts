import { listPendingAccounts, setAccountApproval } from "../../../src/domain/accounts/postgres-platform-accounts.js";
import { applyPortalCors, readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../_http.js";
import { requireOwnerApprover } from "../../_account-auth.js";

type ApprovalInput = { publicRef?: string; action?: "approve" | "suspend" };

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (applyPortalCors(req, res)) return;
  const owner = await requireOwnerApprover(req, res);
  if (!owner) return;
  try {
    if ((req.method ?? "GET") === "GET") {
      writeJson(res, 200, { pending: await listPendingAccounts() });
      return;
    }
    if (req.method === "POST") {
      const body = (readJsonBody(req) ?? {}) as ApprovalInput;
      if (!body.publicRef || !body.action) {
        writeJson(res, 400, { error: "approval_request_invalid" });
        return;
      }
      const account = await setAccountApproval(
        body.publicRef,
        body.action === "approve" ? "active" : "suspended",
        owner.subject,
      );
      if (!account) {
        writeJson(res, 404, { error: "account_not_found" });
        return;
      }
      writeJson(res, 200, { account });
      return;
    }
    writeJson(res, 405, { error: "method_not_allowed" });
  } catch {
    writeJson(res, 503, { error: "account_approval_unavailable" });
  }
}
