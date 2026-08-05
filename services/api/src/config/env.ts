export type RuntimeEnvironment = "local" | "test" | "staging" | "production";

export type PlatformEnv = {
  environment: RuntimeEnvironment;
  port: number;
  databaseUrl?: string;
  publicAppEnv?: string;
  r2AccountId?: string;
  r2AccessKeyId?: string;
  r2SecretAccessKey?: string;
  r2BooksBucket?: string;
  openAiApiKey?: string;
  openAiProjectId?: string;
  appStoreConnectKeyId?: string;
  appStoreConnectIssuerId?: string;
  appStoreConnectPrivateKey?: string;
  apnsKeyId?: string;
  apnsTeamId?: string;
  apnsPrivateKey?: string;
  apnsTopic?: string;
  appleSignInClientId?: string;
  supabaseUrl?: string;
  ownerApproverEmail?: string;
  marketplaceCreatorToken?: string;
  marketplaceOperatorToken?: string;
  sentryDsn?: string;
  marketplaceOperationsEnabled: boolean;
  accountRegistrationEnabled: boolean;
  enableDangerousRoutes: boolean;
  enableRuntimeWrites: boolean;
};

export type RawEnv = Record<string, string | undefined>;

const allowedEnvironments = new Set<RuntimeEnvironment>(["local", "test", "staging", "production"]);

function parseEnvironment(value: string | undefined): RuntimeEnvironment {
  if (!value) return "local";
  if (allowedEnvironments.has(value as RuntimeEnvironment)) return value as RuntimeEnvironment;
  throw new Error(`Unsupported OCTOTEACHER_ENV: ${value}`);
}

function parseBoolean(value: string | undefined): boolean {
  return value === "1" || value === "true";
}

function parsePort(value: string | undefined): number {
  if (!value) return 8787;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65535) {
    throw new Error(`Invalid PORT: ${value}`);
  }
  return parsed;
}

export function loadPlatformEnv(raw: RawEnv = process.env): PlatformEnv {
  const environment = parseEnvironment(raw.OCTOTEACHER_ENV ?? raw.NODE_ENV);

  return {
    environment,
    port: parsePort(raw.PORT),
    databaseUrl: raw.DATABASE_URL,
    publicAppEnv: raw.NEXT_PUBLIC_APP_ENV,
    r2AccountId: raw.R2_ACCOUNT_ID,
    r2AccessKeyId: raw.R2_ACCESS_KEY_ID,
    r2SecretAccessKey: raw.R2_SECRET_ACCESS_KEY,
    r2BooksBucket: raw.R2_BOOKS_BUCKET,
    openAiApiKey: raw.OPENAI_API_KEY,
    openAiProjectId: raw.OPENAI_PROJECT_ID,
    appStoreConnectKeyId: raw.APP_STORE_CONNECT_KEY_ID,
    appStoreConnectIssuerId: raw.APP_STORE_CONNECT_ISSUER_ID,
    appStoreConnectPrivateKey: raw.APP_STORE_CONNECT_PRIVATE_KEY,
    apnsKeyId: raw.APNS_KEY_ID,
    apnsTeamId: raw.APNS_TEAM_ID,
    apnsPrivateKey: raw.APNS_PRIVATE_KEY,
    apnsTopic: raw.APNS_TOPIC,
    appleSignInClientId: raw.APPLE_SIGN_IN_CLIENT_ID,
    supabaseUrl: raw.SUPABASE_URL,
    ownerApproverEmail: raw.OWNER_APPROVER_EMAIL,
    marketplaceCreatorToken: raw.MARKETPLACE_CREATOR_TOKEN,
    marketplaceOperatorToken: raw.MARKETPLACE_OPERATOR_TOKEN,
    sentryDsn: raw.SENTRY_DSN,
    marketplaceOperationsEnabled: parseBoolean(raw.MARKETPLACE_OPERATIONS_ENABLED),
    accountRegistrationEnabled: parseBoolean(raw.ACCOUNT_REGISTRATION_ENABLED),
    enableDangerousRoutes: parseBoolean(raw.OCTOTEACHER_ENABLE_DANGEROUS_ROUTES),
    enableRuntimeWrites: parseBoolean(raw.OCTOTEACHER_ENABLE_RUNTIME_WRITES),
  };
}
