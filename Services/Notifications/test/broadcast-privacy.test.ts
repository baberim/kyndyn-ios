import { describe, expect, it } from "vitest";
import { broadcastPayload } from "../src/broadcast";

describe("broadcast lock-screen privacy", () => {
  it("uses generic content unless the receiving device opted into details", () => {
    expect(broadcastPayload(false, "notice", "Dinner", "At six")).toEqual({
      notificationID: "notice",
      title: "Family announcement",
      body: "Open kyndyn to read it."
    });
  });

  it("includes content after the receiving device opts in", () => {
    expect(broadcastPayload(true, "notice", "Dinner", "At six")).toEqual({
      notificationID: "notice",
      title: "Dinner",
      body: "At six"
    });
  });
});
