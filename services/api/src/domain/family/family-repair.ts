import { FamilyCloudError } from "./cloud-types.js";

export type FamilyRepairCandidate = {
  familyId: string;
  publicRef: string;
  displayName: string;
  createdAt: string;
  guardianIds: string[];
  children: Array<{
    id: string;
    publicRef: string;
    clientRef?: string;
    profileVersion: number;
    updatedAt: string;
  }>;
  counts: {
    devices: number;
    tasks: number;
    pointEntries: number;
    contentItems: number;
    activityEvents: number;
  };
};

export type FamilyRepairPlan = {
  mode: "plan_only";
  targetFamilyId: string;
  sourceFamilyIds: string[];
  requiresOperatorApproval: true;
  conflicts: Array<{
    kind: "child_client_ref";
    clientRef: string;
    profiles: Array<{ familyId: string; childId: string; profileVersion: number; updatedAt: string }>;
  }>;
  phases: string[];
};

export type ExactFamilyRepairSpec = {
  repairRef: string;
  sourceFamilyId: string;
  targetFamilyId: string;
  guardianId: string;
  expectedSourceTaskCount: number;
  expectedSourceActivityCount: number;
  guardianDevicePublicRefs: string[];
  childMappings: Array<{
    clientRef: string;
    sourceChildId: string;
    targetChildId: string;
    childDevicePublicRefs: string[];
  }>;
};

export type ExactFamilyRepairInspection = {
  sourceFamilyStatus?: string;
  targetFamilyStatus?: string;
  sourceMembershipStatus?: string;
  sourceMembershipIsCreator?: boolean;
  sourceTaskCount: number;
  overlappingTaskCount: number;
  regressedTargetTaskCount: number;
  sourceActivityCount: number;
  activeSourceInviteCount: number;
  children: Array<{
    id: string;
    familyId: string;
    clientRef?: string;
    status: string;
    profileVersion: number;
    pointBalance: number;
  }>;
  sourceDevices: Array<{
    publicRef: string;
    role: string;
    guardianId?: string;
    childProfileId?: string;
    status: string;
  }>;
};

export type ExactFamilyRepairValidation = {
  repairRef: string;
  sourceFamilyId: string;
  targetFamilyId: string;
  sourceTaskCount: number;
  activeSourceInviteCount: number;
  guardianDeviceCount: number;
  childDeviceCount: number;
};

export function validateExactFamilyRepair(
  spec: ExactFamilyRepairSpec,
  inspection: ExactFamilyRepairInspection,
): ExactFamilyRepairValidation {
  const reject = (reason: string): never => { throw new FamilyCloudError(`family_repair_${reason}`); };
  if (spec.sourceFamilyId === spec.targetFamilyId) reject("same_family");
  if (inspection.sourceFamilyStatus !== "active") reject("source_not_active");
  if (inspection.targetFamilyStatus !== "active") reject("target_not_active");
  if (inspection.sourceMembershipStatus !== "active" || inspection.sourceMembershipIsCreator !== true) {
    reject("source_guardian_invalid");
  }
  if (inspection.sourceTaskCount !== spec.expectedSourceTaskCount) reject("task_count_changed");
  if (inspection.overlappingTaskCount !== inspection.sourceTaskCount) reject("tasks_not_fully_mirrored");
  if (inspection.regressedTargetTaskCount !== 0) reject("target_task_regression");
  if (inspection.sourceActivityCount !== spec.expectedSourceActivityCount) reject("activity_count_changed");

  const expectedChildIds = new Set(spec.childMappings.flatMap((mapping) => [mapping.sourceChildId, mapping.targetChildId]));
  const inspectedChildren = new Map(inspection.children.map((child) => [child.id, child]));
  if (inspectedChildren.size !== expectedChildIds.size || [...expectedChildIds].some((id) => !inspectedChildren.has(id))) {
    reject("child_set_changed");
  }
  for (const mapping of spec.childMappings) {
    const source = inspectedChildren.get(mapping.sourceChildId);
    const target = inspectedChildren.get(mapping.targetChildId);
    if (!source) throw new FamilyCloudError("family_repair_source_child_missing");
    if (!target) throw new FamilyCloudError("family_repair_target_child_missing");
    if (source.familyId !== spec.sourceFamilyId || source.clientRef !== mapping.clientRef || source.status !== "active") {
      reject("source_child_invalid");
    }
    if (target.familyId !== spec.targetFamilyId || target.clientRef !== mapping.clientRef || target.status !== "active") {
      reject("target_child_invalid");
    }
    if (target.profileVersion < source.profileVersion || target.pointBalance < source.pointBalance) {
      reject("target_child_older");
    }
  }

  const expectedGuardianDevices = new Set(spec.guardianDevicePublicRefs);
  const expectedChildDevices = new Map(spec.childMappings.flatMap((mapping) =>
    mapping.childDevicePublicRefs.map((publicRef) => [publicRef, mapping.sourceChildId] as const)));
  if (inspection.sourceDevices.length !== expectedGuardianDevices.size + expectedChildDevices.size) {
    reject("device_set_changed");
  }
  for (const device of inspection.sourceDevices) {
    if (device.status !== "active") reject("source_device_inactive");
    if (expectedGuardianDevices.has(device.publicRef)) {
      if (device.role !== "guardian" || device.guardianId !== spec.guardianId) reject("guardian_device_invalid");
      continue;
    }
    const sourceChildId = expectedChildDevices.get(device.publicRef);
    if (!sourceChildId || device.role !== "child" || device.childProfileId !== sourceChildId) {
      reject("child_device_invalid");
    }
  }

  return {
    repairRef: spec.repairRef,
    sourceFamilyId: spec.sourceFamilyId,
    targetFamilyId: spec.targetFamilyId,
    sourceTaskCount: inspection.sourceTaskCount,
    activeSourceInviteCount: inspection.activeSourceInviteCount,
    guardianDeviceCount: expectedGuardianDevices.size,
    childDeviceCount: expectedChildDevices.size,
  };
}

export function buildFamilyRepairPlan(
  candidates: FamilyRepairCandidate[],
  targetFamilyId: string,
): FamilyRepairPlan {
  if (candidates.length < 2) throw new FamilyCloudError("family_repair_not_required");
  if (!candidates.some((candidate) => candidate.familyId === targetFamilyId)) {
    throw new FamilyCloudError("family_repair_target_invalid");
  }
  const byClientRef = new Map<string, FamilyRepairPlan["conflicts"][number]["profiles"]>();
  for (const family of candidates) {
    for (const child of family.children) {
      if (!child.clientRef) continue;
      const profiles = byClientRef.get(child.clientRef) ?? [];
      profiles.push({ familyId: family.familyId, childId: child.id,
        profileVersion: child.profileVersion, updatedAt: child.updatedAt });
      byClientRef.set(child.clientRef, profiles);
    }
  }
  const conflicts = [...byClientRef.entries()]
    .filter(([, profiles]) => new Set(profiles.map((profile) => profile.familyId)).size > 1)
    .map(([clientRef, profiles]) => ({ kind: "child_client_ref" as const, clientRef, profiles }));
  return {
    mode: "plan_only",
    targetFamilyId,
    sourceFamilyIds: candidates.map((candidate) => candidate.familyId).filter((id) => id !== targetFamilyId),
    requiresOperatorApproval: true,
    conflicts,
    phases: [
      "Freeze new invites and family writes for source families.",
      "Export target and source families and record an immutable operator audit reference.",
      "Resolve each duplicate child client_ref explicitly; prefer no profile automatically.",
      "Move or deduplicate devices, tasks, point ledger entries, content assignments, and activity by stable references.",
      "Move non-duplicate guardians to the target while preserving the target creator.",
      "Verify balances, task versions, content progress, active child devices, and sync snapshots.",
      "Revoke source sessions and mark source families inactive only after verification and approval.",
    ],
  };
}
