import type {
  FamilyCloudSnapshot,
  FamilyChildSurface,
  FamilyConsole,
  FamilyTaskCloudRecord,
} from "./cloud-types.js";
import { effectiveScreenTimeControlMode } from "./screen-time-control.js";

export type FamilyTaskDelivery =
  | { status: "ready"; reason?: undefined }
  | { status: "quarantined"; reason: string };

function objectValue(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function isHttpsURL(value: unknown): boolean {
  if (typeof value !== "string" || value.length > 4_096) return false;
  try {
    const url = new URL(value);
    return value.toLowerCase().startsWith("https://") && url.protocol === "https:" && url.hostname.length > 0;
  } catch {
    return false;
  }
}

export function classifyFamilyTaskDelivery(payload: unknown): FamilyTaskDelivery {
  if (payload === undefined || payload === null) return { status: "ready" };
  const root = objectValue(payload);
  if (!root) return { status: "quarantined", reason: "invalid_task_payload" };

  const task = objectValue(root.task);
  if (root.version === 2) {
    if (!task) return { status: "quarantined", reason: "invalid_task_payload_v2" };
    const reading = objectValue(task.reading);
    const hasReadingValue = task.reading !== undefined && task.reading !== null;
    if (hasReadingValue && !reading) {
      return { status: "quarantined", reason: "invalid_task_payload_v2" };
    }

    if (!reading) {
      const readingModeIsEmpty = root.readingMode === undefined || root.readingMode === null;
      const readinessIsNotRequired = root.contentReadiness === undefined ||
        root.contentReadiness === "not_required";
      const bookResourceIsEmpty = root.bookResource === undefined || root.bookResource === null;
      return readingModeIsEmpty && readinessIsNotRequired && bookResourceIsEmpty
        ? { status: "ready" }
        : { status: "quarantined", reason: "invalid_task_payload_v2" };
    }

    if (root.readingMode === "physical_manual") {
      return root.contentReadiness === "not_required" &&
        (root.bookResource === undefined || root.bookResource === null)
        ? { status: "ready" }
        : { status: "quarantined", reason: "physical_reading_readiness_invalid" };
    }

    if (root.readingMode === "digital_loaded") {
      const resource = objectValue(root.bookResource);
      return root.contentReadiness === "ready" && resource && isHttpsURL(resource.sourceURLString)
        ? { status: "ready" }
        : { status: "quarantined", reason: "digital_book_resource_missing" };
    }

    return { status: "quarantined", reason: "invalid_task_payload_v2" };
  }

  const legacyReading = task ? objectValue(task.reading) : undefined;
  const legacyMode = legacyReading?.deliveryMode;
  const legacyLooksDigital = objectValue(root.bookResource) !== undefined ||
    root.readingMode === "digital_loaded" || root.readingMode === "digital_required" ||
    legacyMode === "digital_loaded" || legacyMode === "digital_required" ||
    typeof legacyReading?.importedBookId === "string";
  return legacyLooksDigital
    ? { status: "quarantined", reason: "legacy_digital_reading_mode_missing" }
    : { status: "ready" };
}

function taskPayloadParts(task: FamilyTaskCloudRecord): {
  reading: boolean;
  readingMode?: unknown;
  video: boolean;
  videoURL?: unknown;
} {
  const root = objectValue(task.taskPayload);
  const template = objectValue(root?.task);
  const video = objectValue(template?.video);
  return {
    reading: objectValue(template?.reading) !== undefined,
    readingMode: root?.readingMode ?? objectValue(template?.reading)?.deliveryMode,
    video: video !== undefined,
    videoURL: video?.urlString,
  };
}

export function buildFamilyConsole(
  snapshot: FamilyCloudSnapshot,
  tasks: FamilyTaskCloudRecord[],
  aiConfigured: boolean,
  surfaces: FamilyChildSurface[] = [],
  currentGuardian?: { id: string; displayName?: string },
): FamilyConsole {
  return {
    family: snapshot.family,
    currentGuardian: {
      id: currentGuardian?.id ?? "unknown",
      displayName: currentGuardian?.displayName ?? "Guardian",
      isCreator: snapshot.family.isCreator,
    },
    guardians: snapshot.guardians,
    devices: snapshot.devices,
    ai: { configured: aiConfigured },
    children: snapshot.children.map((child) => {
      const childTasks = tasks.filter((task) => task.childProfileId === child.id);
      const summary: FamilyConsole["children"][number]["taskStatusSummary"] = {
        assigned: 0,
        started: 0,
        submitted: 0,
        approved: 0,
        rejected: 0,
        cancelled: 0,
      };
      let readingTotal = 0;
      let readingAvailable = 0;
      let digitalReady = 0;
      let physicalManual = 0;
      let videoTotal = 0;
      let videoAvailable = 0;
      const reminders: FamilyConsole["children"][number]["quarantine"]["reminders"] = [];

      for (const task of childTasks) {
        summary[task.status] += 1;
        const payload = taskPayloadParts(task);
        if (payload.reading) {
          readingTotal += 1;
          if (task.deliveryStatus === "ready") {
            readingAvailable += 1;
            if (payload.readingMode === "digital_loaded") digitalReady += 1;
            if (payload.readingMode === "physical_manual") physicalManual += 1;
          }
        }
        if (payload.video) {
          videoTotal += 1;
          if (task.deliveryStatus === "ready" && isHttpsURL(payload.videoURL)) videoAvailable += 1;
        }
        if (task.deliveryStatus === "quarantined") {
          reminders.push({
            taskId: task.id,
            title: task.title,
            reason: task.quarantineReason ?? "invalid_task_payload",
          });
        }
      }

      const screen = child.screenTimeStatus;
      const screenPolicy = child.screenTimePolicy;
      const hasCompatibleChildDevice = snapshot.devices.some((device) =>
        device.role === "child" &&
        device.status === "active" &&
        device.requiresRebind !== true &&
        device.childProfileId === child.id
      );
      const screenCatalog = child.screenTimeCatalog && snapshot.devices.some((device) =>
        device.role === "child" &&
        device.status === "active" &&
        device.requiresRebind !== true &&
        device.childProfileId === child.id &&
        device.publicRef === child.screenTimeCatalog?.sourceDevicePublicRef
      ) ? child.screenTimeCatalog : undefined;
      const effectiveControlMode = screenPolicy === undefined || screenPolicy === null
        ? "locked"
        : effectiveScreenTimeControlMode(screenPolicy);
      const screenPolicyIsCurrent = hasCompatibleChildDevice &&
        screenPolicy !== undefined &&
        screenPolicy !== null &&
        screen.authorization === "approved" &&
        screen.enforcement === "applied" &&
        screen.appliedPolicyRevision === screenPolicy.revision &&
        screen.appliedSelectionHash === screenPolicy.selectionHash &&
        screen.appliedControlCommandId === screenPolicy.control?.commandId &&
        screen.controlMode === effectiveControlMode;
      const surface = surfaces.find((entry) => entry.child.id === child.id);
      return {
        id: child.id,
        publicRef: child.publicRef,
        displayName: child.displayName,
        growthPointBalance: child.growthPointBalance,
        tasks: childTasks.map((task) => ({
          id: task.id,
          title: task.title,
          status: task.status,
          deliveryStatus: task.deliveryStatus,
          growthPoints: task.growthPoints,
          ...(task.plannedFor === undefined ? {} : { plannedFor: task.plannedFor }),
        })),
        taskStatusSummary: summary,
        availability: {
          reading: { total: readingTotal, available: readingAvailable, digitalReady, physicalManual },
          video: { total: videoTotal, available: videoAvailable },
          screenTime: {
            configured: screenPolicy !== undefined && screenPolicy !== null,
            available: screenPolicyIsCurrent,
            authorization: screen.authorization,
            enforcement: screen.enforcement,
            applicationCount: screen.applicationCount ?? 0,
            categoryCount: screen.categoryCount ?? 0,
            webDomainCount: screen.webDomainCount ?? 0,
            catalogApplicationCount: screenCatalog?.applicationCount ?? 0,
            ...(screenCatalog?.revision === undefined
              ? {} : { catalogRevision: screenCatalog.revision }),
            ...(screenCatalog?.capturedAt === undefined
              ? {} : { catalogCapturedAt: screenCatalog.capturedAt }),
            controlMode: effectiveControlMode,
            ...(child.screenTimePolicy?.control?.commandId === undefined
              ? {} : { controlCommandId: child.screenTimePolicy.control.commandId }),
            ...(screen.appliedControlCommandId === undefined
              ? {} : { appliedControlCommandId: screen.appliedControlCommandId }),
            ...(effectiveControlMode !== "unlocked" ||
                child.screenTimePolicy?.control?.unlockUntil === undefined
              ? {} : { unlockedUntil: child.screenTimePolicy.control.unlockUntil }),
          },
        },
        quarantine: { count: reminders.length, reminders },
        ...(surface ? { surface } : {}),
      };
    }),
  };
}
