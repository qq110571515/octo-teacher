export type RoutePlane = "control" | "runtime" | "internal";
export type RouteMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
export type RouteState = "enabled" | "gated" | "disabled";
export type DataSensitivity =
  | "public"
  | "operational"
  | "child_identity"
  | "child_privacy"
  | "child_health"
  | "ai_transcript"
  | "payment"
  | "credential";

export type RouteDefinition = {
  id: string;
  plane: RoutePlane;
  method: RouteMethod;
  path: string;
  moduleId: string;
  state: RouteState;
  readOnly: boolean;
  requiresAuth: boolean;
  dataSensitivity: DataSensitivity[];
  description: string;
  releaseGateIds?: string[];
};

export type RouteFinding = {
  routeId: string;
  severity: "block" | "warn";
  code: "dangerous_enabled" | "control_plane_write" | "missing_auth" | "credential_exposure";
  message: string;
};
