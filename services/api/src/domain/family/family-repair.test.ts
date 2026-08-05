import assert from "node:assert/strict";
import test from "node:test";
import {
  buildFamilyRepairPlan,
  validateExactFamilyRepair,
  type ExactFamilyRepairInspection,
  type ExactFamilyRepairSpec,
  type FamilyRepairCandidate,
} from "./family-repair.js";

function candidate(familyId: string, childId: string, version: number): FamilyRepairCandidate {
  return {
    familyId, publicRef: `family_${familyId}`, displayName: "Sam Family",
    createdAt: "2026-07-17T00:00:00.000Z", guardianIds: ["guardian-leo"],
    children: [{ id: childId, publicRef: `child_${childId}`, clientRef: "child:sam:stable",
      profileVersion: version, updatedAt: `2026-07-17T00:00:0${version}.000Z` }],
    counts: { devices: 1, tasks: version, pointEntries: 0, contentItems: 0, activityEvents: 0 },
  };
}

test("duplicate families produce a plan without choosing a child profile automatically", () => {
  const plan = buildFamilyRepairPlan([candidate("old", "sam-old", 1), candidate("new", "sam-new", 4)], "new");
  assert.equal(plan.mode, "plan_only");
  assert.deepEqual(plan.sourceFamilyIds, ["old"]);
  assert.equal(plan.conflicts[0]?.clientRef, "child:sam:stable");
  assert.equal(plan.conflicts[0]?.profiles.length, 2);
  assert.equal(plan.requiresOperatorApproval, true);
});

test("repair planning refuses an unknown target", () => {
  assert.throws(() => buildFamilyRepairPlan(
    [candidate("old", "sam-old", 1), candidate("new", "sam-new", 4)], "missing",
  ), /family_repair_target_invalid/);
});

const exactSpec: ExactFamilyRepairSpec = {
  repairRef: "repair:duplicate-family:test",
  sourceFamilyId: "old",
  targetFamilyId: "new",
  guardianId: "guardian-email",
  expectedSourceTaskCount: 83,
  expectedSourceActivityCount: 0,
  guardianDevicePublicRefs: ["ios_guardian"],
  childMappings: [{
    clientRef: "child:sam:stable",
    sourceChildId: "sam-old",
    targetChildId: "sam-new",
    childDevicePublicRefs: ["ios_sam"],
  }],
};

function exactInspection(): ExactFamilyRepairInspection {
  return {
    sourceFamilyStatus: "active", targetFamilyStatus: "active",
    sourceMembershipStatus: "active", sourceMembershipIsCreator: true,
    sourceTaskCount: 83, overlappingTaskCount: 83, regressedTargetTaskCount: 0,
    sourceActivityCount: 0, activeSourceInviteCount: 1,
    children: [
      { id: "sam-old", familyId: "old", clientRef: "child:sam:stable", status: "active",
        profileVersion: 4, pointBalance: 70 },
      { id: "sam-new", familyId: "new", clientRef: "child:sam:stable", status: "active",
        profileVersion: 8, pointBalance: 100 },
    ],
    sourceDevices: [
      { publicRef: "ios_guardian", role: "guardian", guardianId: "guardian-email", status: "active" },
      { publicRef: "ios_sam", role: "child", childProfileId: "sam-old", status: "active" },
    ],
  };
}

test("exact repair accepts only a fully mirrored, newer target", () => {
  const result = validateExactFamilyRepair(exactSpec, exactInspection());
  assert.equal(result.sourceTaskCount, 83);
  assert.equal(result.guardianDeviceCount, 1);
  assert.equal(result.childDeviceCount, 1);
});

test("exact repair rejects missing tasks and lower target balances", () => {
  const missingTask = exactInspection();
  missingTask.overlappingTaskCount = 82;
  assert.throws(() => validateExactFamilyRepair(exactSpec, missingTask), /family_repair_tasks_not_fully_mirrored/);

  const lowerBalance = exactInspection();
  lowerBalance.children[1]!.pointBalance = 60;
  assert.throws(() => validateExactFamilyRepair(exactSpec, lowerBalance), /family_repair_target_child_older/);
});

test("exact repair rejects an unexpected device before changing production data", () => {
  const inspection = exactInspection();
  inspection.sourceDevices.push({ publicRef: "unknown", role: "child", childProfileId: "sam-old", status: "active" });
  assert.throws(() => validateExactFamilyRepair(exactSpec, inspection), /family_repair_device_set_changed/);
});
