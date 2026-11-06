import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const dockerfile = readFileSync(new URL("../../../Dockerfile", import.meta.url), "utf8");

test("the API image installs its packages from the lockfile with npm ci, not npm install", () => {
  assert.match(dockerfile, /^COPY package\.json package-lock\.json \.\/$/m);
  assert.match(dockerfile, /^RUN npm ci --omit=dev --workspace apps\/api --include-workspace-root=false --ignore-scripts$/m);
  // npm ci checks the whole lockfile, so every workspace's package.json is in the image.
  for (const workspace of ["apps/api", "apps/www", "packages/core"]) {
    assert.ok(dockerfile.includes(`COPY ${workspace}/package.json ./${workspace}/package.json`), workspace);
  }
  assert.doesNotMatch(dockerfile, /npm install/);
});
