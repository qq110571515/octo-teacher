import {
  createMarketplaceSubmission,
  listMarketplaceSubmissions,
} from "../../../../src/domain/marketplace/postgres-marketplace-operations.js";
import {
  MarketplaceSubmissionValidationError,
  parseMarketplaceSubmission,
} from "../../../../src/domain/marketplace/submission.js";
import { readJsonBody, writeJson, type ApiRequest, type ApiResponse } from "../../../_http.js";
import { requireMarketplaceOperation } from "../../../_operations-auth.js";

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  const method = req.method ?? "GET";
  try {
    if (method === "POST") {
      if (!requireMarketplaceOperation(req, res, "creator")) return;
      const created = await createMarketplaceSubmission(parseMarketplaceSubmission(readJsonBody(req)));
      writeJson(res, 202, { submission: created });
      return;
    }
    if (method === "GET") {
      if (!requireMarketplaceOperation(req, res, "operator")) return;
      writeJson(res, 200, { submissions: await listMarketplaceSubmissions() });
      return;
    }
    writeJson(res, 405, { error: "method_not_allowed" });
  } catch (error) {
    if (error instanceof MarketplaceSubmissionValidationError) {
      writeJson(res, error.code === "creator_not_available" ? 409 : 400, { error: error.code });
      return;
    }
    if (error instanceof Error && error.message === "invalid_json") {
      writeJson(res, 400, { error: "invalid_json" });
      return;
    }
    writeJson(res, 503, { error: "marketplace_operations_unavailable" });
  }
}
