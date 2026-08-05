import type { RouteDefinition, RouteFinding } from "./types.js";

export class RouteRegistry {
  private readonly routes = new Map<string, RouteDefinition>();

  register(route: RouteDefinition): void {
    if (this.routes.has(route.id)) {
      throw new Error(`Duplicate route id: ${route.id}`);
    }
    this.routes.set(route.id, route);
  }

  list(): RouteDefinition[] {
    return [...this.routes.values()];
  }

  get(routeId: string): RouteDefinition | undefined {
    return this.routes.get(routeId);
  }

  audit(): RouteFinding[] {
    return this.list().flatMap((route) => {
      const findings: RouteFinding[] = [];

      if (route.plane === "control" && !route.readOnly && route.state !== "gated") {
        findings.push({
          routeId: route.id,
          severity: "block",
          code: "control_plane_write",
          message: "Control-plane write routes must be explicitly gated.",
        });
      }

      if (!route.requiresAuth && route.dataSensitivity.some((item) => item !== "public")) {
        findings.push({
          routeId: route.id,
          severity: "block",
          code: "missing_auth",
          message: "Non-public route must require authentication.",
        });
      }

      if (route.state === "enabled" && route.releaseGateIds?.includes("dangerous-side-effect")) {
        findings.push({
          routeId: route.id,
          severity: "block",
          code: "dangerous_enabled",
          message: "Dangerous side-effect route cannot be enabled by default.",
        });
      }

      if (route.dataSensitivity.includes("credential") && route.plane !== "internal") {
        findings.push({
          routeId: route.id,
          severity: "block",
          code: "credential_exposure",
          message: "Credential-sensitive routes must stay internal.",
        });
      }

      return findings;
    });
  }
}
