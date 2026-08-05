import { createHash } from "node:crypto";
import type {
  FamilyChildSurface,
  FamilyChildSurfaceContentItem,
  FamilyChildSurfaceModuleKey,
  FamilyTaskCloudRecord,
} from "./cloud-types.js";

type SurfaceChild = {
  id: string;
  publicRef: string;
  clientRef?: string;
  displayName: string;
  birthYear?: number;
  preReaderMode: boolean;
  interfaceLanguage: "chinese" | "english";
  contentLanguage: "chinese" | "english" | "bilingual";
  growthPointBalance?: number;
  version?: number;
};

type SurfaceContent = Omit<FamilyChildSurfaceContentItem, "assignment"> & { storageObjectKey?: string };
type SurfaceAssignment = FamilyChildSurfaceContentItem["assignment"] & {
  contentItemId: string;
  childProfileId: string;
};

const MODULES: FamilyChildSurface["modules"] = [
  { id: "module:today", key: "today", title: "现在先做", titleEnglish: "Do this now", sortOrder: 100 },
  { id: "module:reading", key: "reading", title: "阅读", titleEnglish: "Reading", sortOrder: 200 },
  { id: "module:video", key: "video", title: "教育视频", titleEnglish: "Educational videos", sortOrder: 300 },
  { id: "module:creation", key: "creation", title: "创作广场", titleEnglish: "Creation plaza", sortOrder: 400 },
  { id: "module:completed", key: "completed", title: "完成回看", titleEnglish: "Completed", sortOrder: 500 },
];

function record(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function taskModule(task: FamilyTaskCloudRecord): FamilyChildSurfaceModuleKey {
  if (["approved", "cancelled"].includes(task.status)) return "completed";
  const root = record(task.taskPayload);
  const template = record(root?.task);
  if (record(template?.reading)) return "reading";
  if (record(template?.video)) return "video";
  if (record(template?.creation) || ["creation", "creative", "art", "music", "craft"]
    .includes(String(template?.category ?? template?.kind ?? "").toLowerCase())) return "creation";
  return "today";
}

function stableRef(value: string): string {
  return value.trim().toLowerCase().replace(/[^a-z0-9._:-]+/g, "-");
}

function taskSort(task: FamilyTaskCloudRecord): number {
  const time = Date.parse(task.plannedFor ?? task.updatedAt);
  return Number.isFinite(time) ? time : 0;
}

function latestCursor(values: Array<string | undefined>): string {
  return values.filter((value): value is string => Boolean(value)).sort().at(-1) ?? "0";
}

function versionOf(value: unknown): string {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex").slice(0, 24);
}

export function buildFamilyChildSurfaces(input: {
  generatedAt?: string;
  children: SurfaceChild[];
  tasks: FamilyTaskCloudRecord[];
  balances?: Array<{ childProfileId: string; balance: number }>;
  taskCursors?: Array<{ childProfileId: string; cursor: string | number }>;
  content?: SurfaceContent[];
  assignments?: SurfaceAssignment[];
}): FamilyChildSurface[] {
  const generatedAt = input.generatedAt ?? new Date().toISOString();
  const balances = new Map((input.balances ?? []).map((entry) => [entry.childProfileId, entry.balance]));
  const taskCursors = new Map((input.taskCursors ?? []).map((entry) => [
    entry.childProfileId,
    Math.max(0, Number(entry.cursor) || 0),
  ]));
  const contentById = new Map((input.content ?? []).map((entry) => {
    const { storageObjectKey: _storageObjectKey, ...safeEntry } = entry;
    return [entry.id, safeEntry] as const;
  }));

  return input.children.map((child) => {
    const tasks = input.tasks
      .filter((task) => task.childProfileId === child.id && task.deliveryStatus === "ready")
      .sort((left, right) => taskSort(left) - taskSort(right) || left.clientRef.localeCompare(right.clientRef))
      .map((task, index) => {
        const module = taskModule(task);
        return {
          itemId: `task:${stableRef(task.clientRef)}`,
          moduleId: `module:${module}`,
          sortOrder: (MODULES.find((entry) => entry.key === module)?.sortOrder ?? 100) * 10_000 + index,
          task,
        };
      });
    const assignedContent = (input.assignments ?? [])
      .filter((assignment) => assignment.childProfileId === child.id && assignment.status !== "removed")
      .flatMap((assignment) => {
        const content = contentById.get(assignment.contentItemId);
        return content && content.availability !== "archived" ? [{ ...content, assignment }] : [];
      })
      .sort((left, right) => left.title.localeCompare(right.title) || left.clientRef.localeCompare(right.clientRef));
    const cursor = latestCursor([
      ...tasks.map((entry) => entry.task.updatedAt),
      ...assignedContent.map((entry) => entry.updatedAt),
      ...assignedContent.map((entry) => entry.assignment.updatedAt),
    ]);
    const stablePayload = {
      child: { ...child, growthPointBalance: balances.get(child.id) ?? child.growthPointBalance ?? 0 },
      modules: MODULES,
      tasks,
      assignedContent,
      cursor,
    };
    return {
      schemaVersion: 1,
      generatedAt,
      cursor,
      surfaceVersion: versionOf(stablePayload),
      child: stablePayload.child,
      modules: MODULES,
      tasks,
      library: {
        books: assignedContent.filter((entry) => entry.kind === "book"),
        videos: assignedContent.filter((entry) => entry.kind === "video"),
        creations: assignedContent.filter((entry) => entry.kind === "creation"),
      },
      sync: {
        taskCursor: taskCursors.get(child.id) ?? 0,
        removedRefs: { tasks: [], content: [] },
      },
    };
  });
}
