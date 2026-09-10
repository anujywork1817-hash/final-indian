import { describe, it, expect } from "vitest";
import App from "./App";

// Smoke test: importing App pulls in its entire component graph
// (UI kit, backgrounds, dashboard sections). If any of those modules
// fail to resolve/parse, this fails — a cheap guard against broken
// imports without needing to render the WebGL/shader-heavy tree in
// jsdom.
describe("App", () => {
  it("loads and exports a React component", () => {
    expect(App).toBeTypeOf("function");
  });
});
