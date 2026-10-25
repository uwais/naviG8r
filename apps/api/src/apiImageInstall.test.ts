import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const dockerfile = readFileSync(new URL("../../../Dockerfile", import.meta.url), "utf8");

test("the API image installs its packages from the lockfile with npm ci, not npm install", () => {
  assert.match(dockerfile, /^COPY package\.json package-lock\.json \.\/$/m);
  assert.match(dockerfile, /^RUN npm ci --workspace apps\/api --ignore-scripts$/m);
  assert.doesNotMatch(dockerfile, /npm install/);
});
