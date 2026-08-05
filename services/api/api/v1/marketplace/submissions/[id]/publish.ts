import { publishMarketplaceSubmission } from "../../../../../src/domain/marketplace/postgres-marketplace-operations.js";
import { MarketplaceSubmissionValidationError } from "../../../../../src/domain/marketplace/submission.js";
import { requirePost, writeJson, type ApiRequest, type ApiResponse } from "../../../../_http.js";
import { requireMarketplaceOperation } from "../../../../_operations-auth.js";

function submissionId(req: ApiRequest): string {
  const raw = req.query?.id;
  const id = Array.isArray(raw) ? raw[0] : raw;
  if (!id || !/^[0-9a-f-]{36}$/i.test(id)) throw new MarketplaceSubmissionValidationError("invalid_submission_id");
  return id;
}

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requirePost(req, res) || !requireMarketplaceOperation(req, res, "operator")) return;
  try {
    writeJson(res, 200, { submission: await publishMarketplaceSubmission(submissionId(req), "marketplace-operator") });
  } catch (error) {
    if (error instanceof MarketplaceSubmissionValidationError) {
      const status = error.code === "submission_not_found" ? 404 : error.code === "submission_not_approved" ? 409 : 400;
      writeJson(res, status, { error: error.code });
      return;
    }
    writeJson(res, 503, { error: "marketplace_publish_unavailable" });
  }
}
