import { describe, expect, it } from "vitest";
import worker, { type Environment } from "../src/index";

const env = { SERVICE_STAGE: "test" } as Environment;

describe("notification service bootstrap", () => {
  it("returns a content-free health response", async () => {
    const response = await worker.fetch(
      new Request("https://notifications.example/health"),
      env
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      service: "kyndyn-notifications",
      status: "ok",
      stage: "test"
    });
  });

  it("keeps notification APIs disabled until authentication is configured", async () => {
    const response = await worker.fetch(
      new Request("https://notifications.example/v1/devices", { method: "POST" }),
      env
    );

    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ error: "service_not_configured" });
  });

  it("does not expose arbitrary routes", async () => {
    const response = await worker.fetch(
      new Request("https://notifications.example/private"),
      env
    );

    expect(response.status).toBe(404);
  });
});
