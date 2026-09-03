import assert from "node:assert/strict";
import test from "node:test";
import { resolveDataFilePath } from "./persistence.ts";

test("resolveDataFilePath uses Postgres when PERSISTENCE=DB", () => {
  assert.equal(resolveDataFilePath({ PERSISTENCE: "DB", DATA_FILE: "/ignored.json" }), null);
});

test("resolveDataFilePath honors explicit DATA_FILE over the production disk default", () => {
  assert.equal(
    resolveDataFilePath(
      { NODE_ENV: "production", DATA_FILE: "/tmp/custom-store.json" },
      { persistentDirExists: true },
    ),
    "/tmp/custom-store.json",
  );
});

test("resolveDataFilePath treats blank DATA_FILE as unset", () => {
  assert.equal(
    resolveDataFilePath({ NODE_ENV: "production", DATA_FILE: "   " }, { persistentDirExists: true }),
    "/data/store.json",
  );
});

test("production with Render /data disk defaults to the persistent volume", () => {
  assert.equal(
    resolveDataFilePath({ NODE_ENV: "production" }, { persistentDirExists: true }),
    "/data/store.json",
  );
});

test("production without /data keeps the local relative default", () => {
  assert.equal(
    resolveDataFilePath({ NODE_ENV: "production" }, { persistentDirExists: false }),
    "./data/store.json",
  );
});

test("non-production keeps the relative default even if /data exists", () => {
  assert.equal(
    resolveDataFilePath({ NODE_ENV: "development" }, { persistentDirExists: true }),
    "./data/store.json",
  );
  assert.equal(resolveDataFilePath({}, { persistentDirExists: true }), "./data/store.json");
});
