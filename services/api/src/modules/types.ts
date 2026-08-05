import type { DataSensitivity, RouteDefinition } from "../routing/types.js";

export type ModulePriority = "P0" | "P1" | "P2" | "P3";
export type ModuleStatus = "planned" | "scaffolded" | "dry_run" | "gated" | "enabled";

export type ModuleDependency = {
  moduleId: string;
  optional?: boolean;
  reason: string;
};

export type ModuleReleaseGate = {
  id: string;
  title: string;
  required: boolean;
  status: "missing" | "watch" | "passed";
};

export type ModuleManifest = {
  id: string;
  title: string;
  owner: string;
  status: ModuleStatus;
  priority: ModulePriority;
  docs: string[];
  capabilities: string[];
  dependencies: ModuleDependency[];
  dataSensitivity: DataSensitivity[];
  routes: RouteDefinition[];
  eventsProduced: string[];
  eventsConsumed: string[];
  workflowHooks: string[];
  releaseGates: ModuleReleaseGate[];
};

export type ModuleRegistryFinding = {
  moduleId: string;
  severity: "block" | "warn";
  code: "missing_owner" | "missing_docs" | "missing_capability" | "missing_dependency" | "release_gate_missing";
  message: string;
};
