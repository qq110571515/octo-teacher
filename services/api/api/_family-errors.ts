import { FamilyCloudError } from "../src/domain/family/cloud-types.js";
import { capturePlatformError } from "../src/observability/sentry.js";
import { writeJson, type ApiResponse } from "./_http.js";

const conflicts = new Set([
  "guardian_already_in_family",
  "invite_invalid_or_expired",
  "task_not_submittable",
  "task_not_withdrawable",
  "stale_task_version",
  "stale_child_profile_version",
  "emergency_request_in_progress",
  "emergency_request_mismatch",
  "emergency_request_expired",
  "emergency_approval_expired",
  "emergency_session_expired",
  "emergency_request_not_expired",
  "emergency_approval_not_expired",
  "emergency_session_not_expired",
  "invalid_emergency_transition",
  "approved_task_award_immutable",
  "points_mutation_ref_conflict",
  "points_source_ref_conflict",
  "points_mutation_conflict",
  "insufficient_growth_points",
  "activity_client_ref_conflict",
  "portal_link_consumed",
  "portal_link_expired",
  "portal_link_unavailable",
  "portal_guardian_already_linked",
  "portal_account_already_linked",
  "portal_apple_identity_already_linked",
  "portal_account_not_active",
  "email_device_code_expired",
  "email_device_code_unavailable",
  "guardian_multiple_active_families",
  "guardian_family_conflict",
  "child_client_ref_family_conflict",
  "content_mutation_ref_conflict",
  "stale_family_version",
  "stale_content_version",
  "stale_content_assignment_version",
  "child_profile_archived",
  "family_must_keep_one_child",
  "duplicate_child_name",
  "stale_screen_time_policy",
  "stale_screen_time_catalog_binding",
  "device_role_conflict",
  "child_device_rebind_required",
  "child_device_protocol_unsupported",
]);
const forbidden = new Set([
  "family_access_denied",
  "family_creator_required",
  "guardian_account_inactive",
  "screen_time_emergency_access_denied",
  "activity_child_access_denied",
  "guardian_self_revoke_forbidden",
  "family_creator_revoke_forbidden",
]);
const identityConflicts = new Set([
  "guardian_account_identity_conflict",
  "guardian_identity_account_conflict",
  "guardian_identity_family_conflict",
]);
const notFound = new Set([
  "child_profile_not_found",
  "device_not_found",
  "portal_link_not_found",
  "portal_family_not_linked",
  "email_device_code_not_found",
  "guardian_membership_not_found",
  "content_not_found",
]);
const unauthorized = new Set(["guardian_session_required"]);
const upgradeRequired = new Set(["child_device_update_required"]);

export function writeFamilyError(res: ApiResponse, error: unknown, fallback: string): void {
  if (error instanceof FamilyCloudError) {
    const status = unauthorized.has(error.code) ? 401 : upgradeRequired.has(error.code) ? 426 : forbidden.has(error.code) ? 403 : notFound.has(error.code) ? 404 :
      conflicts.has(error.code) || identityConflicts.has(error.code) ? 409 :
      error.code === "nonce_rate_limited" || error.code === "email_device_rate_limited" ? 429 : 400;
    writeJson(res, status, { error: error.code });
    return;
  }
  if (error instanceof Error && error.message === "invalid_json") {
    writeJson(res, 400, { error: "invalid_json" });
    return;
  }
  if (error instanceof Error && error.message === "apple_sign_in_not_configured") {
    writeJson(res, 503, { error: error.message });
    return;
  }
  if (error instanceof Error && conflicts.has(error.message)) {
    writeJson(res, 409, { error: error.message, repairable: true });
    return;
  }
  capturePlatformError(fallback, "family-api");
  writeJson(res, 503, { error: fallback });
}
