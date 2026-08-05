import * as Sentry from "@sentry/node";

let initialized = false;

function initialize(): void {
  if (initialized || !process.env.SENTRY_DSN) return;
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.APP_ENV ?? process.env.VERCEL_ENV ?? "development",
    sendDefaultPii: false,
    tracesSampleRate: 0,
    beforeSend(event) {
      delete event.request;
      delete event.user;
      return event;
    },
  });
  initialized = true;
}

export function capturePlatformError(code: string, source: string): void {
  initialize();
  if (!initialized) return;
  const sanitized = new Error(code);
  sanitized.name = "OctoTeacherPlatformError";
  Sentry.withScope((scope) => {
    scope.setTag("octoteacher.source", source);
    scope.setFingerprint([source, code]);
    Sentry.captureException(sanitized);
  });
}
