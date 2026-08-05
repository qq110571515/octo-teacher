import type { DataSensitivity } from "../routing/types.js";

export type ActorRole = "child" | "guardian" | "teacher" | "expert" | "creator" | "moderator" | "operator" | "worker";
export type PermissionAction = "read" | "write" | "approve" | "publish" | "execute_side_effect";

export type PermissionRequest = {
  actorId: string;
  role: ActorRole;
  familyId?: string;
  childId?: string;
  action: PermissionAction;
  resource: string;
  dataSensitivity: DataSensitivity[];
};

export type PermissionDecision = {
  allowed: boolean;
  reasonCode: string;
  explanation: string;
};

export interface PermissionGate {
  decide(request: PermissionRequest): PermissionDecision;
}
