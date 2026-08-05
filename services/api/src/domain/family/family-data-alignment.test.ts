import assert from "node:assert/strict";
import test from "node:test";
import { shouldAwardTaskGrowthPoints } from "./family-growth-points.js";
import { resolveGuardianTaskStatus } from "./family-task-sync.js";

test("child submission, cloud review, and parent approval remain aligned", () => {
  const childCloudStatus = "submitted" as const;

  // A parent's stale local copy cannot overwrite the child's cloud submission.
  const preservedForParent = resolveGuardianTaskStatus(childCloudStatus, "assigned");
  assert.equal(preservedForParent, "submitted");

  // The parent can approve that same cloud record, and points settle once only.
  const approved = resolveGuardianTaskStatus(preservedForParent, "approved");
  assert.equal(approved, "approved");
  assert.equal(shouldAwardTaskGrowthPoints(preservedForParent, approved), true);
  assert.equal(shouldAwardTaskGrowthPoints(approved, approved), false);
});
