import { reviewMarketplaceSubmission } from "../../../../../src/domain/marketplace/postgres-marketplace-operations.js";
import {
  MarketplaceSubmissionValidationError,
  type MarketplaceReviewDecision,
} from "../../../../../src/domain/marketplace/submission.js";
import { readJsonBody, requirePost, writeJson, type ApiRequest, type ApiResponse } from "../../../../_http.js";
import { requireMarketplaceOperation } from "../../../../_operations-auth.js";

function submissionId(req: ApiRequest): string {
  const raw = req.query?.id;
  const id = Array.isArray(raw) ? raw[0] : raw;
  if (!id || !/^[0-9a-f-]{36}$/i.test(id)) throw new MarketplaceSubmissionValidationError("invalid_submission_id");
  return id;
}

function reviewBody(value: unknown): { decision: MarketplaceReviewDecision; notes?: string } {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new MarketplaceSubmissionValidationError("invalid_review");
  const input = value as Record<string, unknown>;
  if (!new Set(["approve", "request_changes", "reject"]).has(String(input.decision))) {
    throw new MarketplaceSubmissionValidationError("invalid_review_decision");
  }
  if (input.notes !== undefined && (typeof input.notes !== "string" || input.notes.trim().length > 2_000)) {
    throw new MarketplaceSubmissionValidationError("invalid_review_notes");
  }
  return {
    decision: input.decision as MarketplaceReviewDecision,
    ...(typeof input.notes === "string" && input.notes.trim() ? { notes: input.notes.trim() } : {}),
  };
}

export default async function handler(req: ApiRequest, res: ApiResponse): Promise<void> {
  if (!requirePost(req, res) || !requireMarketplaceOperation(req, res, "operator")) return;
  try {
    const body = reviewBody(readJsonBody(req));
    const submission = await reviewMarketplaceSubmission(submissionId(req), body.decision, body.notes, "marketplace-operator");
    writeJson(res, 200, { submission });
  } catch (error) {
    if (error instanceof MarketplaceSubmissionValidationError) {
      const status = error.code === "submission_not_found" ? 404 : error.code === "invalid_review_transition" ? 409 : 400;
      writeJson(res, status, { error: error.code });
      return;
    }
    if (error instanceof Error && error.message === "invalid_json") {
      writeJson(res, 400, { error: "invalid_json" });
      return;
    }
    writeJson(res, 503, { error: "marketplace_review_unavailable" });
  }
}
