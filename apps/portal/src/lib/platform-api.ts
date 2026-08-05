import type { Session } from "@supabase/supabase-js";

export const platformApiPaths = {
  account: "/api/v1/account",
  accountApprovals: "/api/v1/account/approvals",
  accountFamily: "/api/v1/account/family",
  accountFamilyChildren: "/api/v1/account/family/children",
  accountFamilyDevices: "/api/v1/account/family/devices",
  accountFamilyGuardians: "/api/v1/account/family/guardians",
  accountFamilyLink: "/api/v1/account/family/link",
  accountFamilyScreenTimeControl: "/api/v1/account/family/screen-time/control",
  appLoginApprove: "/api/v1/account/app-login/approve",
} as const;

export type FamilyTaskStatus =
  | "assigned"
  | "started"
  | "submitted"
  | "approved"
  | "rejected"
  | "cancelled";

export type FamilyActivityKind = "task" | "reading" | "video" | "creation" | "screen_time";

export type FamilyChildSurfaceModuleKey =
  | "today"
  | "reading"
  | "video"
  | "creation"
  | "completed";

export type FamilyChildSurfaceContent = {
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
    progressPercent?: number;
    durationSeconds?: number;
    version: number;
    updatedAt: string;
  };
  version: number;
  updatedAt: string;
};

export type FamilyChildSurface = {
  schemaVersion: number;
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
    task: {
      id: string;
      childProfileId: string;
      clientRef: string;
      title: string;
      titleEnglish?: string;
      status: FamilyTaskStatus;
      deliveryStatus: "ready" | "quarantined";
      growthPoints: number;
      requiresEvidence: boolean;
      plannedFor?: string;
      evidenceSummary?: string;
      taskPayload?: unknown;
      version: number;
      updatedAt: string;
    };
  }>;
  library: {
    books: FamilyChildSurfaceContent[];
    videos: FamilyChildSurfaceContent[];
    creations: FamilyChildSurfaceContent[];
  };
  sync: {
    taskCursor: number;
    removedRefs: {
      tasks: string[];
      content: string[];
    };
  };
};

export type FamilyDirectory = {
  guardians: Array<{
    id: string;
    displayName: string;
    isCreator: boolean;
    joinedAt?: string;
  }>;
  devices: Array<{
    id: string;
    displayName: string;
    role: "guardian" | "child";
    childProfileId?: string;
    status: "active" | "revoked";
    boundAt?: string;
  }>;
};

export type PortalFamilyCapability =
  | "family_rename"
  | "family_directory"
  | "child_profile_update"
  | "device_revoke";

export type FamilyConsole = {
  family: {
    id: string;
    publicRef: string;
    displayName: string;
    createdAt?: string;
    updatedAt?: string;
    isCreator: boolean;
  };
  currentGuardian: {
    id: string;
    displayName: string;
    isCreator: boolean;
  };
  guardians: Array<{
    id: string;
    displayName: string;
    isCreator: boolean;
    joinedAt?: string;
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
  ai: { configured: boolean };
  lastSyncedAt?: string;
  children: Array<{
    id: string;
    publicRef: string;
    displayName: string;
    growthPointBalance: number;
    lastSyncedAt?: string;
    surface?: FamilyChildSurface;
    tasks: Array<{
      id: string;
      title: string;
      titleEnglish?: string;
      status: FamilyTaskStatus;
      deliveryStatus: "ready" | "quarantined";
      growthPoints: number;
      plannedFor?: string;
    }>;
    taskStatusSummary: Record<FamilyTaskStatus, number>;
    availability: {
      reading: {
        total: number;
        available: number;
        digitalReady: number;
        physicalManual: number;
      };
      video: { total: number; available: number };
      screenTime: {
        configured: boolean;
        available: boolean;
        authorization: "not_requested" | "approved" | "denied" | "unavailable" | "error";
        enforcement: "waiting_for_authorization" | "waiting_for_policy" | "ready" | "applied" | "error";
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
    activity?: {
      windowDays: number;
      durationSeconds: Record<FamilyActivityKind, number>;
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
        kind: FamilyActivityKind;
        occurredAt: string;
        durationSeconds?: number;
        progressPercent?: number;
        displayName: string;
        resourceRef?: string;
      }>;
    };
    quarantine: {
      count: number;
      reminders: Array<{ taskId: string; title: string; reason: string }>;
    };
  }>;
};

export class PlatformApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
  ) {
    super(code);
    this.name = "PlatformApiError";
  }
}

export class PlatformCapabilityUnavailableError extends Error {
  constructor(readonly capability: PortalFamilyCapability) {
    super(`portal_capability_unavailable:${capability}`);
    this.name = "PlatformCapabilityUnavailableError";
  }
}

const apiBase = process.env.NEXT_PUBLIC_PLATFORM_API_URL?.replace(/\/$/, "") ?? "";

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function responseErrorCode(payload: unknown): string {
  if (!isRecord(payload)) return "request_failed";
  for (const key of ["error", "code", "message"] as const) {
    if (typeof payload[key] === "string" && payload[key].length > 0) return payload[key];
  }
  return "request_failed";
}

function looksLikeFamilyConsole(value: unknown): value is FamilyConsole {
  if (!isRecord(value) || !isRecord(value.family) || !Array.isArray(value.children)) return false;
  return typeof value.family.displayName === "string";
}

// Keep response-envelope knowledge here so UI components stay stable if the API wraps data later.
function unwrapFamilyConsole(payload: unknown): FamilyConsole {
  if (looksLikeFamilyConsole(payload)) return payload;
  if (!isRecord(payload)) throw new PlatformApiError(200, "invalid_family_console_response");

  for (const key of ["console", "familyConsole", "data", "result"] as const) {
    if (looksLikeFamilyConsole(payload[key])) return payload[key];
    if (isRecord(payload[key]) && looksLikeFamilyConsole(payload[key].family)) return payload[key].family;
  }
  if (looksLikeFamilyConsole(payload.family)) return payload.family;

  throw new PlatformApiError(200, "invalid_family_console_response");
}

export async function platformRequest<T>(
  session: Session,
  path: string,
  init?: RequestInit,
): Promise<T> {
  const headers = new Headers(init?.headers);
  headers.set("accept", "application/json");
  headers.set("authorization", `Bearer ${session.access_token}`);
  if (init?.body !== undefined && !headers.has("content-type")) {
    headers.set("content-type", "application/json");
  }

  const response = await fetch(`${apiBase}${path}`, {
    ...init,
    cache: "no-store",
    headers,
  });

  const text = await response.text();
  let payload: unknown = undefined;
  if (text.length > 0) {
    try {
      payload = JSON.parse(text);
    } catch {
      payload = undefined;
    }
  }

  if (!response.ok) {
    throw new PlatformApiError(response.status, responseErrorCode(payload));
  }
  return payload as T;
}

export async function loadAccountFamily(session: Session): Promise<FamilyConsole | null> {
  try {
    const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
    const path = `${platformApiPaths.accountFamily}?timeZone=${encodeURIComponent(timeZone)}`;
    const payload = await platformRequest<unknown>(session, path);
    return unwrapFamilyConsole(payload);
  } catch (error) {
    if (error instanceof PlatformApiError && (error.status === 404 || error.status === 409)) {
      return null;
    }
    throw error;
  }
}

export async function linkAccountFamily(session: Session, code: string): Promise<void> {
  await platformRequest<unknown>(session, platformApiPaths.accountFamilyLink, {
    method: "POST",
    body: JSON.stringify({ code }),
  });
}

export async function createAccountFamilyChild(
  session: Session,
  input: { displayName: string; age: number },
): Promise<void> {
  await platformRequest<unknown>(session, platformApiPaths.accountFamilyChildren, {
    method: "POST",
    body: JSON.stringify(input),
  });
}

export async function archiveAccountFamilyChild(session: Session, childId: string): Promise<void> {
  await platformRequest<unknown>(session, platformApiPaths.accountFamilyChildren, {
    method: "DELETE",
    body: JSON.stringify({ childId }),
  });
}

export async function updateAccountFamilyScreenTimeControl(
  session: Session,
  childProfileId: string,
  action: "lock" | "unlock",
  minutes?: number,
): Promise<void> {
  await platformRequest<unknown>(session, platformApiPaths.accountFamilyScreenTimeControl, {
    method: "PUT",
    body: JSON.stringify({
      childProfileId,
      action,
      ...(minutes === undefined ? {} : { minutes }),
    }),
  });
}

// These typed calls define the portal contract without pretending that a write succeeded.
// The account-scoped API currently exposes only the read console and one-time family link.
export async function renameAccountFamily(
  session: Session,
  familyId: string,
  displayName: string,
): Promise<void> {
  void familyId;
  await platformRequest<unknown>(session, platformApiPaths.accountFamily, {
    method: "PATCH",
    body: JSON.stringify({ displayName }),
  });
}

export async function loadAccountFamilyDirectory(session: Session): Promise<never> {
  void session;
  throw new PlatformCapabilityUnavailableError("family_directory");
}

export async function updateAccountFamilyChild(
  session: Session,
  childId: string,
  input: { displayName?: string },
): Promise<never> {
  void session;
  void childId;
  void input;
  throw new PlatformCapabilityUnavailableError("child_profile_update");
}

export async function revokeAccountFamilyDevice(
  session: Session,
  deviceId: string,
): Promise<void> {
  await platformRequest<unknown>(session, platformApiPaths.accountFamilyDevices, {
    method: "DELETE",
    body: JSON.stringify({ deviceId }),
  });
}

export async function revokeAccountFamilyGuardian(
  session: Session,
  guardianId: string,
): Promise<void> {
  await platformRequest<unknown>(session, platformApiPaths.accountFamilyGuardians, {
    method: "DELETE",
    body: JSON.stringify({ guardianId }),
  });
}

export async function deleteAccountFamily(
  session: Session,
  publicRef: string,
): Promise<{ receiptId: string; deletedAt: string }> {
  return platformRequest(session, platformApiPaths.accountFamily, {
    method: "DELETE",
    body: JSON.stringify({ confirmation: `DELETE ${publicRef}` }),
  });
}
