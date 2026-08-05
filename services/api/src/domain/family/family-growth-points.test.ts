import assert from "node:assert/strict";
import test from "node:test";
import { FamilyCloudError } from "./cloud-types.js";
import { normalizeGrowthPointMutation, shouldAwardTaskGrowthPoints } from "./family-growth-points.js";

test("growth-point mutations enforce kind-specific delta signs and stable refs", () => {
  assert.deepEqual(normalizeGrowthPointMutation({
    mutationRef: "screen-spend:123",
    kind: "screen_time_spend",
    delta: -15,
    sourceRef: "screen-session:123",
  }), {
    mutationRef: "screen-spend:123",
    kind: "screen_time_spend",
    delta: -15,
    sourceRef: "screen-session:123",
  });
  assert.deepEqual(normalizeGrowthPointMutation({
    mutationRef: "screen-refund:123",
    kind: "screen_time_refund",
    delta: 15,
    sourceRef: "screen-session:123",
  }).kind, "screen_time_refund");

  assert.throws(() => normalizeGrowthPointMutation({
    mutationRef: "screen-spend:123",
    kind: "screen_time_spend",
    delta: 15,
    sourceRef: "screen-session:123",
  }), (error) => error instanceof FamilyCloudError && error.code === "invalid_points_delta");
  assert.throws(() => normalizeGrowthPointMutation({
    mutationRef: "short",
    kind: "screen_time_refund",
    delta: 1,
    sourceRef: "screen-session:123",
  }), (error) => error instanceof FamilyCloudError && error.code === "invalid_mutation_ref");
});

test("task approval awards only on the first transition into approved", () => {
  assert.equal(shouldAwardTaskGrowthPoints(undefined, "approved"), true);
  assert.equal(shouldAwardTaskGrowthPoints("submitted", "approved"), true);
  assert.equal(shouldAwardTaskGrowthPoints("approved", "approved"), false);
  assert.equal(shouldAwardTaskGrowthPoints("approved", "rejected"), false);
  assert.equal(shouldAwardTaskGrowthPoints("submitted", "rejected"), false);
});
