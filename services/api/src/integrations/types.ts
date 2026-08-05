export type IntegrationProvider =
  | "vercel"
  | "postgres"
  | "cloudflare_r2"
  | "openai"
  | "apple_app_store_connect"
  | "apple_sign_in"
  | "apple_push_notifications"
  | "resend"
  | "stripe"
  | "sentry"
  | "marketplace_operations";

export type IntegrationEnvironment = "local" | "test" | "staging" | "production";
export type IntegrationStatus = "planned" | "configured" | "missing_secret" | "disabled";

export type SecretRef = {
  id: string;
  envName: string;
  required: boolean;
  holder: "server" | "worker" | "deployment_platform";
};

export type PlatformIntegration = {
  provider: IntegrationProvider;
  environment: IntegrationEnvironment;
  status: IntegrationStatus;
  purpose: string;
  secretRefs: SecretRef[];
  dangerousCapabilities: string[];
  publicConfigKeys: string[];
};

export type IntegrationFinding = {
  provider: IntegrationProvider;
  severity: "block" | "warn";
  code: "missing_required_secret" | "dangerous_capability_enabled" | "secret_in_public_config";
  message: string;
};
