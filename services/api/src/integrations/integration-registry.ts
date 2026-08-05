import type { IntegrationFinding, IntegrationStatus, PlatformIntegration, SecretRef } from "./types.js";

export class IntegrationRegistry {
  private readonly integrations: PlatformIntegration[];

  constructor(integrations: PlatformIntegration[]) {
    this.integrations = integrations;
  }

  list(): PlatformIntegration[] {
    return this.integrations.map((integration) => ({
      ...integration,
      secretRefs: integration.secretRefs.map((secret) => ({ ...secret })),
      dangerousCapabilities: [...integration.dangerousCapabilities],
      publicConfigKeys: [...integration.publicConfigKeys],
    }));
  }

  audit(availableEnv: Record<string, string | undefined>): IntegrationFinding[] {
    return this.integrations.flatMap((integration) => {
      const findings: IntegrationFinding[] = [];

      for (const secret of integration.secretRefs) {
        if (secret.required && !availableEnv[secret.envName]) {
          findings.push({
            provider: integration.provider,
            severity: "block",
            code: "missing_required_secret",
            message: `Missing required secret env ${secret.envName}.`,
          });
        }

        if (integration.publicConfigKeys.includes(secret.envName)) {
          findings.push({
            provider: integration.provider,
            severity: "block",
            code: "secret_in_public_config",
            message: `Secret env ${secret.envName} is exposed as public config.`,
          });
        }
      }

      if (integration.status === "configured" && integration.dangerousCapabilities.length > 0) {
        findings.push({
          provider: integration.provider,
          severity: "warn",
          code: "dangerous_capability_enabled",
          message: "Dangerous integration capability requires workflow release evidence before production use.",
        });
      }

      return findings;
    });
  }
}

function deriveStatus(status: IntegrationStatus, secretRefs: SecretRef[], availableEnv: Record<string, string | undefined>): IntegrationStatus {
  const requiredSecrets = secretRefs.filter((secret) => secret.required);

  if (requiredSecrets.length === 0) return status;
  if (requiredSecrets.every((secret) => Boolean(availableEnv[secret.envName]))) return "configured";

  return status;
}

export function defaultPlatformIntegrations(
  environment: "local" | "test" | "staging" | "production" = "local",
  availableEnv: Record<string, string | undefined> = {},
): PlatformIntegration[] {
  const vercelSecrets: SecretRef[] = [{ id: "vercel-project-id", envName: "VERCEL_PROJECT_ID", required: false, holder: "deployment_platform" }];
  const postgresSecrets: SecretRef[] = [{ id: "database-url", envName: "DATABASE_URL", required: true, holder: "server" }];
  const r2Secrets: SecretRef[] = [
    { id: "r2-account-id", envName: "R2_ACCOUNT_ID", required: true, holder: "server" },
    { id: "r2-access-key-id", envName: "R2_ACCESS_KEY_ID", required: true, holder: "server" },
    { id: "r2-secret-access-key", envName: "R2_SECRET_ACCESS_KEY", required: true, holder: "server" },
    { id: "r2-books-bucket", envName: "R2_BOOKS_BUCKET", required: true, holder: "server" },
  ];
  const openAiSecrets: SecretRef[] = [
    { id: "openai-api-key", envName: "OPENAI_API_KEY", required: true, holder: "server" },
    { id: "openai-admin-key", envName: "OPENAI_ADMIN_API_KEY", required: false, holder: "worker" },
  ];
  const appStoreSecrets: SecretRef[] = [
    { id: "app-store-key-id", envName: "APP_STORE_CONNECT_KEY_ID", required: true, holder: "worker" },
    { id: "app-store-issuer-id", envName: "APP_STORE_CONNECT_ISSUER_ID", required: true, holder: "worker" },
    { id: "app-store-private-key", envName: "APP_STORE_CONNECT_PRIVATE_KEY", required: true, holder: "worker" },
  ];
  const apnsRequired = environment === "production";
  const apnsSecrets: SecretRef[] = [
    { id: "apns-key-id", envName: "APNS_KEY_ID", required: apnsRequired, holder: "server" },
    { id: "apns-team-id", envName: "APNS_TEAM_ID", required: apnsRequired, holder: "server" },
    { id: "apns-private-key", envName: "APNS_PRIVATE_KEY", required: apnsRequired, holder: "server" },
  ];
  const marketplaceOperationSecrets: SecretRef[] = [
    { id: "marketplace-creator-token", envName: "MARKETPLACE_CREATOR_TOKEN", required: true, holder: "server" },
    { id: "marketplace-operator-token", envName: "MARKETPLACE_OPERATOR_TOKEN", required: true, holder: "server" },
  ];
  const sentrySecrets: SecretRef[] = [
    { id: "sentry-dsn", envName: "SENTRY_DSN", required: true, holder: "server" },
  ];

  return [
    {
      provider: "vercel",
      environment,
      status: "planned",
      purpose: "Deploy console and API routes with environment-scoped configuration.",
      secretRefs: vercelSecrets,
      dangerousCapabilities: [],
      publicConfigKeys: ["NEXT_PUBLIC_APP_ENV"],
    },
    {
      provider: "postgres",
      environment,
      status: deriveStatus("missing_secret", postgresSecrets, availableEnv),
      purpose: "Durable family, event, workflow, audit, book, and usage storage.",
      secretRefs: postgresSecrets,
      dangerousCapabilities: ["persistent-write"],
      publicConfigKeys: [],
    },
    {
      provider: "cloudflare_r2",
      environment,
      status: deriveStatus("missing_secret", r2Secrets, availableEnv),
      purpose: "Cloud book repository, covers, proof assets, and signed downloads.",
      secretRefs: r2Secrets,
      dangerousCapabilities: ["asset-publish"],
      publicConfigKeys: [],
    },
    {
      provider: "openai",
      environment,
      status: deriveStatus("missing_secret", openAiSecrets, availableEnv),
      purpose: "Server-side AI proxy, model routing, safety review, and token cost metering.",
      secretRefs: openAiSecrets,
      dangerousCapabilities: ["ai-provider-call"],
      publicConfigKeys: [],
    },
    {
      provider: "apple_app_store_connect",
      environment,
      status: deriveStatus("missing_secret", appStoreSecrets, availableEnv),
      purpose: "Download, sales, subscription, and app analytics report synchronization.",
      secretRefs: appStoreSecrets,
      dangerousCapabilities: [],
      publicConfigKeys: [],
    },
    {
      provider: "apple_sign_in",
      environment,
      status: availableEnv.APPLE_SIGN_IN_CLIENT_ID ? "configured" : "planned",
      purpose: "Guardian account sign-in and account linking.",
      secretRefs: [],
      dangerousCapabilities: [],
      publicConfigKeys: ["APPLE_SIGN_IN_CLIENT_ID"],
    },
    {
      provider: "apple_push_notifications",
      environment,
      status: deriveStatus(apnsRequired ? "missing_secret" : "planned", apnsSecrets, availableEnv),
      purpose: "Guardian notifications, invite reminders, and high-risk safety escalation.",
      secretRefs: apnsSecrets,
      dangerousCapabilities: ["push-notification-send"],
      publicConfigKeys: ["APNS_TOPIC"],
    },
    {
      provider: "resend",
      environment,
      status: "planned",
      purpose: "Guardian email invites, sign-in codes, and operational notices.",
      secretRefs: [{ id: "resend-api-key", envName: "RESEND_API_KEY", required: false, holder: "server" }],
      dangerousCapabilities: ["email-send"],
      publicConfigKeys: [],
    },
    {
      provider: "stripe",
      environment,
      status: "planned",
      purpose: "Future web/creator/school billing; iOS digital goods remain StoreKit-first.",
      secretRefs: [
        { id: "stripe-secret-key", envName: "STRIPE_SECRET_KEY", required: false, holder: "server" },
        { id: "stripe-webhook-secret", envName: "STRIPE_WEBHOOK_SECRET", required: false, holder: "server" },
      ],
      dangerousCapabilities: ["payment-capture"],
      publicConfigKeys: ["STRIPE_PUBLIC_KEY"],
    },
    {
      provider: "sentry",
      environment,
      status: deriveStatus("missing_secret", sentrySecrets, availableEnv),
      purpose: "API and dashboard error monitoring with privacy-safe event scrubbing.",
      secretRefs: sentrySecrets,
      dangerousCapabilities: [],
      publicConfigKeys: ["NEXT_PUBLIC_SENTRY_DSN"],
    },
    {
      provider: "marketplace_operations",
      environment,
      status: deriveStatus("missing_secret", marketplaceOperationSecrets, availableEnv),
      purpose: "Creator submission and operator review credentials for the training marketplace write lane.",
      secretRefs: marketplaceOperationSecrets,
      dangerousCapabilities: ["catalog-publish"],
      publicConfigKeys: [],
    },
  ];
}
