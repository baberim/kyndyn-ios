import { provisionHousehold, registerDevice, revokeDevice } from "./enrollment";
import { hasValidServerKey } from "./crypto";
import { RequestError } from "./validation";

export interface Environment {
  DB: D1Database;
  DEVICE_TOKEN_ENCRYPTION_KEY: string;
  SERVICE_STAGE: string;
}

type HealthResponse = {
  service: "kyndyn-notifications";
  status: "ok";
  stage: string;
};

const json = (body: unknown, status = 200): Response =>
  Response.json(body, {
    status,
    headers: {
      "cache-control": "no-store",
      "content-security-policy": "default-src 'none'",
      "x-content-type-options": "nosniff"
    }
  });

const secure = (response: Response): Response => {
  response.headers.set("cache-control", "no-store");
  response.headers.set("content-security-policy", "default-src 'none'");
  response.headers.set("x-content-type-options", "nosniff");
  return response;
};

const requireEnrollmentConfiguration = (env: Environment): void => {
  if (!hasValidServerKey(env.DEVICE_TOKEN_ENCRYPTION_KEY)) {
    throw new RequestError(
      503,
      "service_not_configured",
      "Notification enrollment is not enabled."
    );
  }
};

export default {
  async fetch(request: Request, env: Environment): Promise<Response> {
    try {
      const url = new URL(request.url);

      if (request.method === "GET" && url.pathname === "/health") {
        const response: HealthResponse = {
          service: "kyndyn-notifications",
          status: "ok",
          stage: env.SERVICE_STAGE
        };
        return json(response);
      }

      if (request.method === "POST" && url.pathname === "/v1/households/provision") {
        requireEnrollmentConfiguration(env);
        return secure(await provisionHousehold(request, env));
      }
      if (request.method === "POST" && url.pathname === "/v1/devices/register") {
        requireEnrollmentConfiguration(env);
        return secure(await registerDevice(request, env));
      }
      if (request.method === "POST" && url.pathname === "/v1/devices/revoke") {
        requireEnrollmentConfiguration(env);
        return secure(await revokeDevice(request, env));
      }

      if (url.pathname.startsWith("/v1/")) {
        return json(
          {
            error: "service_not_configured",
            message: "Notification delivery is not enabled."
          },
          503
        );
      }

      return json({ error: "not_found" }, 404);
    } catch (error) {
      if (error instanceof RequestError) {
        return json({ error: error.code, message: error.message }, error.status);
      }
      console.error("notification_request_failed", {
        category: error instanceof Error ? error.name : "unknown"
      });
      return json({ error: "internal_error", message: "The request could not be completed." }, 500);
    }
  }
} satisfies ExportedHandler<Environment>;
