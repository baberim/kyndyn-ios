export interface Environment {
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

export default {
  async fetch(request: Request, env: Environment): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      const response: HealthResponse = {
        service: "kyndyn-notifications",
        status: "ok",
        stage: env.SERVICE_STAGE
      };
      return json(response);
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
  }
} satisfies ExportedHandler<Environment>;
