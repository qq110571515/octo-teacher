import http2 from "node:http2";
import { importPKCS8, SignJWT } from "jose";
import { FamilyCloudError } from "./cloud-types.js";

export type ChildPushEnvironment = "development" | "production";

export type ChildPushRegistration = {
  token: string;
  environment: ChildPushEnvironment;
};

export type ScreenTimeWakePush = {
  token: string;
  environment: ChildPushEnvironment;
  revision?: number;
  commandId?: string;
};

type APNsConfiguration = {
  keyId: string;
  teamId: string;
  privateKey: string;
  topic: string;
};

let cachedProviderToken: { value: string; expiresAt: number; cacheKey: string } | undefined;

function optionalText(value: string | undefined): string | undefined {
  const normalized = value?.trim();
  return normalized ? normalized : undefined;
}
function apnsConfiguration(): APNsConfiguration | undefined {
  const keyId = optionalText(process.env.APNS_KEY_ID);
  const teamId = optionalText(process.env.APNS_TEAM_ID);
  const rawPrivateKey = optionalText(process.env.APNS_PRIVATE_KEY);
  if (!keyId || !teamId || !rawPrivateKey) return undefined;
  return {
    keyId,
    teamId,
    privateKey: rawPrivateKey.replace(/\\n/g, "\n"),
    topic: optionalText(process.env.APNS_TOPIC) ?? "com.octoteacher.app",
  };
}

export function normalizeChildPushRegistration(value: unknown): ChildPushRegistration {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new FamilyCloudError("invalid_push_registration");
  }
  const raw = value as Record<string, unknown>;
  const token = typeof raw.token === "string" ? raw.token.trim().toLowerCase() : "";
  const environment = raw.environment;
  if (!/^[0-9a-f]{64,200}$/.test(token)) {
    throw new FamilyCloudError("invalid_push_token");
  }
  if (environment !== "development" && environment !== "production") {
    throw new FamilyCloudError("invalid_push_environment");
  }
  return { token, environment };
}

export function screenTimeWakePayload(input: Pick<ScreenTimeWakePush, "revision" | "commandId">) {
  return {
    aps: { "content-available": 1 },
    octoteacher: {
      kind: "screen_time_sync",
      ...(input.revision === undefined ? {} : { revision: input.revision }),
      ...(input.commandId === undefined ? {} : { commandId: input.commandId }),
    },
  };
}

async function providerToken(config: APNsConfiguration): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const cacheKey = `${config.teamId}:${config.keyId}`;
  if (cachedProviderToken &&
      cachedProviderToken.cacheKey === cacheKey &&
      cachedProviderToken.expiresAt > now + 60) {
    return cachedProviderToken.value;
  }
  const privateKey = await importPKCS8(config.privateKey, "ES256");
  const value = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: config.keyId })
    .setIssuer(config.teamId)
    .setIssuedAt(now)
    .sign(privateKey);
  cachedProviderToken = { value, expiresAt: now + 50 * 60, cacheKey };
  return value;
}

async function sendPush(
  config: APNsConfiguration,
  input: ScreenTimeWakePush,
): Promise<void> {
  const authorization = await providerToken(config);
  const host = input.environment === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
  const body = JSON.stringify(screenTimeWakePayload(input));

  await new Promise<void>((resolve, reject) => {
    const client = http2.connect(host);
    const timeout = setTimeout(() => {
      client.destroy();
      reject(new Error("apns_timeout"));
    }, 5_000);
    client.once("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    const request = client.request({
      ":method": "POST",
      ":path": `/3/device/${input.token}`,
      authorization: `bearer ${authorization}`,
      "apns-topic": config.topic,
      "apns-push-type": "background",
      "apns-priority": "5",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 5 * 60),
      "content-type": "application/json",
      "content-length": Buffer.byteLength(body),
    });
    let responseBody = "";
    let status = 0;
    request.setEncoding("utf8");
    request.on("response", (headers) => {
      status = Number(headers[":status"] ?? 0);
    });
    request.on("data", (chunk: string) => {
      responseBody += chunk;
    });
    request.once("error", (error) => {
      clearTimeout(timeout);
      client.close();
      reject(error);
    });
    request.on("end", () => {
      clearTimeout(timeout);
      client.close();
      if (status >= 200 && status < 300) {
        resolve();
      } else {
        reject(new Error(`apns_${status}:${responseBody.slice(0, 160)}`));
      }
    });
    request.end(body);
  });
}

export async function sendScreenTimeWakePushes(
  registrations: ScreenTimeWakePush[],
): Promise<{ configured: boolean; attempted: number; delivered: number }> {
  const config = apnsConfiguration();
  if (!config || registrations.length === 0) {
    return { configured: config !== undefined, attempted: 0, delivered: 0 };
  }
  const results = await Promise.allSettled(
    registrations.map((registration) => sendPush(config, registration)),
  );
  return {
    configured: true,
    attempted: registrations.length,
    delivered: results.filter((result) => result.status === "fulfilled").length,
  };
}
