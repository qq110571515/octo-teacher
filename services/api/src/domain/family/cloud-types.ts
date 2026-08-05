export type GuardianSessionContext = {
  sessionId: string;
  guardianId: string;
  displayName?: string;
  devicePublicRef: string;
};

export type ChildDeviceSessionContext = {
  deviceId: string;
  familyId: string;
  childProfileId: string;
  devicePublicRef: string;
  protocolGeneration: number;
};

export type FamilyExchangePolicyPayload = {
  allowanceCycle?: "monthly" | "weekly" | "daily";
  baseMonthlyAllowance: number;
  allowanceDayOfMonth: number;
  screenRate: "one_point_per_minute" | "two_points_per_minute" | "one_point_per_two_minutes";
  customScreenPointsPer15Minutes?: number;
  customScreenExchangeMinutes?: number;
  pointsPerCurrencyUnit: number;
  pocketMoneyRequiresApproval: boolean;
  monthlyPocketMoneyCap?: number;
  currencySymbol: string;
};

export type FamilyScreenTimePolicyPayload = {
  schemaVersion: 3;
  revision: number;
  selectionData: string;
  selectionHash: string;
  applicationCount: number;
  categoryCount: number;
  webDomainCount: number;
  catalogBinding?: {
    revision: number;
    selectionHash: string;
  };
  control?: FamilyScreenTimeControlPayload;
  updatedAt: string;
};

export type FamilyScreenTimeCatalogPayload = {
  schemaVersion: 1;
  revision: number;
  selectionData: string;
  selectionHash: string;
  applicationCount: number;
  categoryCount: number;
  webDomainCount: number;
  capturedAt: string;
  sourceDevicePublicRef: string;
};

export type FamilyScreenTimeSelectionPayload = Pick<
  FamilyScreenTimePolicyPayload,
  | "schemaVersion"
  | "selectionData"
  | "selectionHash"
  | "applicationCount"
  | "categoryCount"
  | "webDomainCount"
>;

export type FamilyScreenTimeControlPayload = {
  schemaVersion: 1;
  commandId: string;
  mode: "locked" | "unlocked";
  issuedAt: string;
  unlockUntil?: string;
};

export type FamilyScreenTimeStatusPayload = {
  authorization: "not_requested" | "approved" | "denied" | "unavailable" | "error";
  enforcement: "waiting_for_authorization" | "waiting_for_policy" | "ready" | "applied" | "error";
  appliedPolicyRevision?: number;
  appliedSelectionHash?: string;
  appliedControlCommandId?: string;
  controlMode?: "locked" | "unlocked";
  unlockedUntil?: string;
  lastErrorCode?: string;
  applicationCount?: number;
  categoryCount?: number;
  webDomainCount?: number;
  updatedAt: string;
};

type FamilyScreenTimeEmergencyRequestBase = {
  schemaVersion: 1;
  requestId: string;
  reason: string;
  minutes: number;
  requestedAt: string;
  updatedAt: string;
};

type FamilyScreenTimeEmergencyApprovalBase = FamilyScreenTimeEmergencyRequestBase & {
  decidedAt: string;
  approvalExpiresAt: string;
};

type FamilyScreenTimeEmergencyActiveBase = FamilyScreenTimeEmergencyApprovalBase & {
  activatedAt: string;
  sessionEndsAt: string;
};

export type FamilyScreenTimeEmergencyPayload =
  | {
      schemaVersion: 1;
      status: "idle";
      updatedAt: string;
    }
  | (FamilyScreenTimeEmergencyRequestBase & {
      status: "requested";
    })
  | (FamilyScreenTimeEmergencyApprovalBase & {
      status: "approved";
    })
  | (FamilyScreenTimeEmergencyRequestBase & {
      status: "denied";
      decidedAt: string;
    })
  | (FamilyScreenTimeEmergencyActiveBase & {
      status: "active";
    })
  | (FamilyScreenTimeEmergencyActiveBase & {
      status: "completed";
      completedAt: string;
    })
  | (FamilyScreenTimeEmergencyRequestBase & {
      status: "expired";
      expiredAt: string;
      expirationReason: "request_timeout";
    })
  | (FamilyScreenTimeEmergencyApprovalBase & {
      status: "expired";
      expiredAt: string;
      expirationReason: "approval_timeout";
    })
  | (FamilyScreenTimeEmergencyActiveBase & {
      status: "expired";
      expiredAt: string;
      expirationReason: "session_timeout";
    });

export type FamilyCloudSnapshot = {
  family: {
    id: string;
    publicRef: string;
    displayName: string;
    isCreator: boolean;
  };
  guardians: Array<{
    id: string;
    displayName: string;
    isCreator: boolean;
    joinedAt?: string;
  }>;
  children: Array<{
    id: string;
    publicRef: string;
    clientRef?: string;
    displayName: string;
    birthYear?: number;
    preReaderMode: boolean;
    interfaceLanguage: "chinese" | "english";
    contentLanguage: "chinese" | "english" | "bilingual";
    dailyLimitMinutes: number;
    exchangePolicy: FamilyExchangePolicyPayload;
    screenTimeCatalog?: FamilyScreenTimeCatalogPayload;
    screenTimePolicy?: FamilyScreenTimePolicyPayload;
    screenTimeStatus: FamilyScreenTimeStatusPayload;
    screenTimeEmergency: FamilyScreenTimeEmergencyPayload;
    growthPointBalance: number;
    profileVersion: number;
  }>;
  devices: Array<{
    id: string;
    publicRef: string;
    displayName: string;
    role: "guardian" | "child";
    childProfileId?: string;
    status: "active" | "revoked";
    boundAt: string;
    protocolGeneration?: number;
    requiresRebind?: boolean;
  }>;
};

export type FamilyTaskCloudRecord = {
  id: string;
  childProfileId: string;
  clientRef: string;
  title: string;
  titleEnglish?: string;
  status: "assigned" | "started" | "submitted" | "approved" | "rejected" | "cancelled";
  growthPoints: number;
  requiresEvidence: boolean;
  plannedFor?: string;
  evidenceSummary?: string;
  taskPayload?: unknown;
  deliveryStatus: "ready" | "quarantined";
  quarantineReason?: string;
  version: number;
  updatedAt: string;
};

export type FamilyChildSurfaceModuleKey = "today" | "reading" | "video" | "creation" | "completed";

export type FamilyChildSurfaceContentItem = {
  id: string;
  publicRef: string;
  clientRef: string;
  kind: "book" | "video" | "creation";
  title: string;
  titleEnglish?: string;
  sourceKind: "marketplace" | "cloud_library" | "guardian_upload" | "external" | "generated";
  sourceRef?: string;
  availability: "processing" | "ready" | "unavailable" | "archived";
  metadata: Record<string, string | number | boolean | null>;
  assignment: {
    status: string;
    progressPercent: number;
    durationSeconds: number;
    version: number;
    updatedAt: string;
  };
  version: number;
  updatedAt: string;
};

export type FamilyChildSurface = {
  schemaVersion: 1;
  generatedAt: string;
  cursor: string;
  surfaceVersion: string;
  child: {
    id: string;
    publicRef: string;
    clientRef?: string;
    displayName: string;
    birthYear?: number;
    preReaderMode: boolean;
    interfaceLanguage: "chinese" | "english";
    contentLanguage: "chinese" | "english" | "bilingual";
    growthPointBalance: number;
  };
  modules: Array<{
    id: string;
    key: FamilyChildSurfaceModuleKey;
    title: string;
    titleEnglish: string;
    sortOrder: number;
  }>;
  tasks: Array<{
    itemId: string;
    moduleId: string;
    sortOrder: number;
    task: FamilyTaskCloudRecord;
  }>;
  library: {
    books: FamilyChildSurfaceContentItem[];
    videos: FamilyChildSurfaceContentItem[];
    creations: FamilyChildSurfaceContentItem[];
  };
  sync: {
    taskCursor: number;
    removedRefs: {
      tasks: string[];
      content: string[];
    };
  };
};

export type FamilyGrowthPointMutationKind = "screen_time_spend" | "screen_time_refund";

export type FamilyGrowthPointMutationResult = {
  balance: number;
  applied: boolean;
};

export type ScreenTimeRedemptionReservation = {
  id: string;
  redemptionRef: string;
  state: "reserved" | "committed" | "cancelled" | "expired";
  points: number;
  expiresAt: string;
  balance: number;
};

export type FamilyConsole = {
  family: FamilyCloudSnapshot["family"];
  currentGuardian: {
    id: string;
    displayName: string;
    isCreator: boolean;
  };
  guardians: FamilyCloudSnapshot["guardians"];
  devices: FamilyCloudSnapshot["devices"];
  ai: { configured: boolean };
  children: Array<{
    id: string;
    publicRef: string;
    displayName: string;
    growthPointBalance: number;
    tasks: Array<{
      id: string;
      title: string;
      status: FamilyTaskCloudRecord["status"];
      deliveryStatus: FamilyTaskCloudRecord["deliveryStatus"];
      growthPoints: number;
      plannedFor?: string;
    }>;
    taskStatusSummary: Record<FamilyTaskCloudRecord["status"], number>;
    availability: {
      reading: { total: number; available: number; digitalReady: number; physicalManual: number };
      video: { total: number; available: number };
      screenTime: {
        configured: boolean;
        available: boolean;
        authorization: FamilyScreenTimeStatusPayload["authorization"];
        enforcement: FamilyScreenTimeStatusPayload["enforcement"];
        applicationCount: number;
        categoryCount: number;
        webDomainCount: number;
        catalogApplicationCount: number;
        catalogRevision?: number;
        catalogCapturedAt?: string;
        controlMode: "locked" | "unlocked";
        controlCommandId?: string;
        appliedControlCommandId?: string;
        unlockedUntil?: string;
      };
    };
    quarantine: {
      count: number;
      reminders: Array<{ taskId: string; title: string; reason: string }>;
    };
    surface?: FamilyChildSurface;
    activity?: {
      windowDays: 90;
      durationSeconds: Record<"task" | "reading" | "video" | "screen_time" | "creation", number>;
      screenTimeDaily: Array<{
        date: string;
        durationSeconds: number;
        eventCount: number;
      }>;
      screenTimeAppDaily: Array<{
        date: string;
        appRef: string;
        authority: string;
        durationSeconds: number;
        eventCount: number;
      }>;
      recent: Array<{
        eventId: string;
        kind: "task" | "reading" | "video" | "screen_time" | "creation";
        occurredAt: string;
        durationSeconds?: number;
        progressPercent?: number;
        displayName: string;
        resourceRef?: string;
      }>;
    };
  }>;
};

export type ChildDeviceProfile = FamilyCloudSnapshot["children"][number] & {
  family: { id: string; publicRef: string; displayName: string };
};

export type FamilyTaskSyncPage = {
  tasks: FamilyTaskCloudRecord[];
  removedClientRefs: string[];
  cursor: number;
  hasMore: boolean;
};

export type FamilyCloudExport = {
  exportVersion: string;
  exportedAt: string;
  scope: "cloud_family_minimal_sync";
  scopeNote: string;
  family: FamilyCloudSnapshot;
  tasks: FamilyTaskCloudRecord[];
  audit: Array<{
    action: string;
    actorKind: "guardian" | "child_device" | "system";
    targetPublicRef?: string;
    createdAt: string;
  }>;
};

export class FamilyCloudError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "FamilyCloudError";
  }
}
