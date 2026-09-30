/** V1 is a separate presentation over the same authenticated APIs as V2. */
export function adminDashboardV1Html(operations = false): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>NaviG8r · Full dashboard</title><style>
*{box-sizing:border-box}body{margin:0;background:#f3f6fa;color:#182c45;font:15px system-ui,-apple-system,sans-serif}button,input,select{font:inherit}a{color:#225a9c}button,a,input,select{outline-offset:4px}button{cursor:pointer;border:1px solid #c6d1df;border-radius:8px;background:white;padding:10px 15px;color:#203754;font-weight:600}button:hover{background:#edf3f9}button:disabled{opacity:.55;cursor:default}.primary{background:#153d66;color:white;border-color:#153d66}.primary:hover{background:#21517d}.danger{color:#a02d34}header{background:#102d4e;color:white;padding:20px 32px;display:flex;gap:24px;align-items:center;justify-content:space-between}header a{color:#d5e9ff}header strong{font-size:23px;letter-spacing:-.6px}header small{color:#bdd0e4}.badge{display:inline-block;padding:4px 8px;border-radius:5px;background:#d9e9fa;color:#204770;font-size:12px}.header-links{display:flex;gap:20px;align-items:center}main{max-width:1600px;margin:auto;padding:28px 32px}h1{font-size:30px;letter-spacing:-.7px;margin:0 0 6px}h2{font-size:19px;margin:0 0 16px}h3{font-size:16px;margin:0 0 12px}.muted{color:#5c6c80;font-size:13px}.card{background:white;border:1px solid #dce3ec;border-radius:12px;padding:22px;box-shadow:0 2px 5px #17324c04}.login{max-width:430px;margin:7vh auto}.login p{line-height:1.6}label{display:block;font-size:13px;font-weight:600;margin:12px 0 5px}input,select{width:100%;padding:10px;border:1px solid #b8c6d6;border-radius:7px;background:white;color:#182c45;min-width:0}input[type=checkbox]{width:auto}.login button{margin-top:16px}.session{display:flex;align-items:end;gap:18px;margin:22px 0}.session>div{max-width:430px;flex:1}.session label{margin-top:0}.notice{padding:12px 16px;border-radius:8px;margin:14px 0;overflow-wrap:anywhere}.notice:empty{display:none}#error{background:#fcecee;color:#8e2430}#notice{background:#e4f4ef;color:#1f6750}.tabs{display:flex;flex-wrap:wrap;gap:8px;margin:22px 0}.tabs button[aria-selected=true]{background:#153d66;color:white;border-color:#153d66}.toolbar{display:flex;align-items:end;gap:12px;flex-wrap:wrap;margin-bottom:18px}.toolbar>div{flex:1;min-width:180px}.table-wrap{overflow:auto;max-height:590px}table{border-collapse:collapse;width:100%;min-width:650px;font-size:13px}th{text-align:left;background:#f0f4f8;color:#53657b;padding:12px;position:sticky;top:0;white-space:nowrap}td{border-bottom:1px solid #e8edf3;padding:13px 12px;max-width:250px;overflow-wrap:anywhere;vertical-align:top}tbody tr:hover{background:#f8fafc}.pagination{display:flex;gap:12px;align-items:center;justify-content:flex-end;margin-top:18px}.pagination span{margin-right:auto}.grid{display:grid;align-items:start;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:18px;margin:18px 0}.grid form{display:flex;flex-direction:column}.grid form button{margin-top:18px;align-self:start}.grid p{line-height:1.5}.section-title{margin-top:30px}.review-row{display:flex;gap:10px;align-items:center;flex-wrap:wrap;border-top:1px solid #e3eaf2;padding:14px 0}.review-row>div{flex:1;min-width:200px}.review-row small{display:block;color:#526078;margin-top:5px}details{margin-top:16px}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px;background:#f3f6fa;padding:14px;border-radius:6px;max-height:280px;overflow:auto}[hidden]{display:none!important}footer{margin-top:28px;color:#66788b;font-size:12px}@media(max-width:650px){header{padding:18px;align-items:start}.header-links{flex-direction:column;gap:8px;align-items:end}main{padding:20px 14px}h1{font-size:25px}.session{flex-wrap:wrap}.session>div{min-width:100%}.grid{grid-template-columns:1fr}.card{padding:17px}.tabs{gap:6px}.tabs button{padding:8px 10px;font-size:13px}}
</style></head><body><header><div><strong>NaviG8r</strong><br><small>Operations & administration · V1</small></div><div class="header-links"><a href="${operations ? "/ops/v2" : "/admin/v2"}">Compact dashboard (V2)</a><a href="/workflow">Shipment / POD workspace</a></div></header><main>
<section id="login" class="card login"><span class="badge">FULL DASHBOARD</span><h1 style="margin-top:16px">Welcome back</h1><p class="muted">Sign in to manage your authorized operations, accounts and payments.</p><form id="send-code"><label for="phone">Phone number</label><input id="phone" autocomplete="tel" required placeholder="10-digit phone number"><button class="primary">Send code</button></form><form id="verify-code"><label for="code">Verification code</label><input id="code" autocomplete="one-time-code" required placeholder="6-digit code"><button>Sign in</button></form></section>
<div id="error" class="notice" role="alert"></div><div id="notice" class="notice" role="status"></div>
<section id="workspace" hidden><h1>${operations ? "Operations workspace" : "Full dashboard"}</h1><p class="muted">Your workspace, with the tools your role allows.</p><div class="session"><div><label for="organization">Acting organization</label><select id="organization"><option value="">Select an organization</option></select></div><span id="roles" class="badge"></span><button id="refresh">Refresh access</button><button id="signout">Sign out</button></div><p id="access" class="muted"></p>
<div id="protected" hidden><nav id="tabs" class="tabs" aria-label="Dashboard sections"></nav><section class="card"><h2 id="table-title">Records</h2><form id="search" class="toolbar"><div><label for="query">Search records</label><input id="query" placeholder="Name, organization or ID"></div><div id="target-org-field" hidden><label for="target-org">Target organization ID</label><input id="target-org" placeholder="Customer or carrier organization ID"></div><div><label for="status">Status</label><input id="status" placeholder="Optional exact status"></div><label id="inactive-label" hidden><input id="inactive" type="checkbox"> Include inactive</label><button>Search</button></form><div id="table" class="table-wrap"></div><div class="pagination"><span id="count" class="muted"></span><button id="previous">Previous</button><button id="next">Next</button></div><details id="details" hidden><summary>Selected record</summary><pre id="record"></pre></details></section>
<h2 class="section-title">Actions</h2><p class="muted">Changes apply to both dashboard versions. Review the target before confirming.</p><div id="actions" class="grid"></div>
<section id="compliance" class="card" hidden><h2>Carrier compliance review</h2><p class="muted">Review carriers independently of bank setup. Approval enables acceptance and trip start when payment checks also pass.</p><label for="review-reason">Review reason code</label><input id="review-reason" placeholder="DOCUMENTS_REVIEWED"><div id="queue"></div></section>
</div></section><footer>Full dashboard V1 · Access is checked for each request.</footer></main><script>const operations = ${operations};
${dashboardClient}
</script></body></html>`;
}

const dashboardClient = String.raw`
const $ = (id) => document.getElementById(id);
let token = sessionStorage.getItem("navig8r_access") || "",
  org = sessionStorage.getItem("navig8r_org") || "",
  challenge = "",
  principal,
  section = "",
  offset = 0,
  generation = 0,
  tableGeneration = 0,
  saving = false;
const sections = [
  ["carriers", "Carriers", "directory.read"],
  ["organizations", "Organizations", "directory.read"],
  ["users", "Users", "user.role_manage"],
  ["memberships", "Memberships", "user.role_manage"],
  ["vehicles", "Vehicles", "fleet.read"],
  ["drivers", "Driver profiles", "fleet.read"],
  ["trips", "Anchor trips", "load.read"],
  ["shipments", "Shipments", "load.read"],
  ["ledger", "Ledger lines", "finance"],
  ["payouts", "Payout batches", "finance"],
  ["members", "Assistance members", "trip.publish"],
];
function can(permission) {
  return (
    principal &&
    (permission === "finance"
      ? principal.roles.includes("FINANCE")
      : principal.permissions.includes(permission))
  );
}
function clearProtected() {
  generation++;
  principal = undefined;
  $("protected").hidden = true;
  $("table").replaceChildren();
  $("actions").replaceChildren();
  $("tabs").replaceChildren();
  $("queue").replaceChildren();
  $("record").textContent = "";
  $("details").hidden = true;
  $("roles").textContent = "";
  $("notice").textContent = "";
}
const otpErrors = {
  otp_expired: "This code has expired. Request a new code and try again.",
  otp_incorrect: "That code is incorrect. Check it and try again.",
  otp_challenge_invalid: "This code request is no longer valid. Request a new code.",
  otp_challenge_not_found: "This code request is no longer valid. Request a new code.",
  otp_challenge_mismatch: "This code request is no longer valid. Request a new code.",
};
async function request(path, method = "GET", body, extra = {}) {
  const g = generation,
    response = await fetch(path, {
      method,
      headers: {
        "content-type": "application/json",
        ...(token ? { authorization: "Bearer " + token } : {}),
        ...(org ? { "x-organization-id": org } : {}),
        ...extra,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  const out = await response.json();
  if (g !== generation)
    throw Error("Workspace changed. Refresh to see the latest state.");
  if (!response.ok) {
    if (
      response.status === 401 ||
      (response.status === 403 && out.error !== "payment_hold_active")
    ) {
      clearProtected();
      $("access").textContent =
        "Access changed. Refresh access or sign in again.";
      if (response.status === 401) {
        token = "";
        sessionStorage.removeItem("navig8r_access");
        $("login").hidden = false;
        $("workspace").hidden = true;
      }
    }
    throw Error(otpErrors[out.error] || out.error || "Request failed");
  }
  return out;
}
const perform = (fn) => async (e) => {
  if (e) e.preventDefault();
  $("error").textContent = "";
  try {
    await fn(e);
  } catch (error) {
    $("error").textContent = error.message;
  }
};
$("send-code").onsubmit = perform(async () => {
  challenge = "";
  $("code").value = "";
  $("notice").textContent = "";
  const out = await request("/v1/auth/otp/start", "POST", {
    phone: $("phone").value,
  });
  challenge = typeof out.challengeId === "string" ? out.challengeId : "";
  if (!challenge) throw Error("OTP start returned no challenge. Request a new code.");
  if (typeof out.debugCode === "string" && /^\d{6}$/.test(out.debugCode)) {
    $("code").value = out.debugCode;
  }
  $("notice").textContent = "Code sent. Enter it to sign in.";
});
$("verify-code").onsubmit = perform(async () => {
  if (!challenge) throw Error("Request a code before signing in.");
  const out = await request("/v1/auth/otp/verify", "POST", {
    phone: $("phone").value,
    challengeId: challenge,
    code: $("code").value,
  });
  token = out.accessToken;
  org = "";
  sessionStorage.setItem("navig8r_access", token);
  sessionStorage.removeItem("navig8r_org");
  await load();
});
$("signout").onclick = () => {
  clearProtected();
  sessionStorage.removeItem("navig8r_access");
  sessionStorage.removeItem("navig8r_org");
  location.reload();
};
$("refresh").onclick = perform(load);
$("organization").onchange = perform(async () => {
  org = $("organization").value;
  sessionStorage.setItem("navig8r_org", org);
  clearProtected();
  await load();
});
async function load() {
  clearProtected();
  const me = await request("/v1/auth/me");
  $("login").hidden = true;
  $("workspace").hidden = false;
  $("organization").replaceChildren(new Option("Select an organization", ""));
  for (const o of me.organizations)
    $("organization").append(new Option(o.displayName, o.id));
  if (!org && me.organizations.length === 1) {
    org = me.organizations[0].id;
    sessionStorage.setItem("navig8r_org", org);
  }
  $("organization").value = org;
  principal = org ? (await request("/v1/auth/me")).principal : undefined;
  if (!principal) {
    $("access").textContent = "Select an active organization to continue.";
    return;
  }
  $("roles").textContent = principal.roles.join(" · ");
  if (
    !principal.internal ||
    !principal.roles.some((r) => ["ADMIN", "OPS", "FINANCE"].includes(r))
  ) {
    $("access").textContent =
      "Use the Shipment / POD workspace for your organization. Internal dashboard records are unavailable for this membership.";
    return;
  }
  $("access").textContent =
    "Showing authorized sections for the selected organization.";
  $("protected").hidden = false;
  const available = sections.filter((s) => can(s[2]));
  if (!available.some((s) => s[0] === section))
    section =
      operations && available.some((s) => s[0] === "shipments")
        ? "shipments"
        : available[0]?.[0];
  for (const s of available) {
    const b = document.createElement("button");
    b.textContent = s[1];
    b.setAttribute("aria-selected", String(s[0] === section));
    b.onclick = perform(async () => {
      section = s[0];
      offset = 0;
      $("query").value = "";
      $("status").value = "";
      await table();
    });
    $("tabs").append(b);
  }
  $("inactive-label").hidden = !can("user.role_manage");
  if (!can("user.role_manage")) $("inactive").checked = false;
  actions();
  await table();
  $("compliance").hidden = !can("kyc.verify");
  if (can("kyc.verify")) await queue();
}
async function table() {
  if (!section) return;
  const selected = section,
    g = generation,
    tableRequest = ++tableGeneration;
  $("target-org-field").hidden = section !== "members";
  if (section === "members" && !$("target-org").value) {
    $("table-title").textContent = "Assistance members";
    $("table").replaceChildren();
    $("count").textContent =
      "Enter a customer or carrier organization ID and click Search.";
    return;
  }
  const params = new URLSearchParams({
    targetOrgId: $("target-org").value,
    q: $("query").value,
    status: $("status").value,
    offset: String(offset),
    limit: "15",
    inactive: String($("inactive").checked),
  });
  const out = await request("/v1/ops/dashboard/" + section + "?" + params);
  if (
    selected !== section ||
    g !== generation ||
    tableRequest !== tableGeneration
  )
    return;
  $("details").hidden = true;
  $("record").textContent = "";
  $("table-title").textContent = sections.find((s) => s[0] === section)[1];
  [...$("tabs").children].forEach((b) =>
    b.setAttribute(
      "aria-selected",
      String(b.textContent === $("table-title").textContent),
    ),
  );
  $("table").replaceChildren();
  $("count").textContent =
    out.total + " records" + (out.mode ? " · Payout mode: " + out.mode : "");
  $("previous").disabled = offset === 0;
  $("next").disabled = offset + out.items.length >= out.total;
  if (!out.items.length) {
    const p = document.createElement("p");
    p.className = "muted";
    p.textContent = "No records match this view.";
    $("table").append(p);
    return;
  }
  const preferred = {
    carriers: ["displayName", "kind", "kycStatus", "id"],
    organizations: ["displayName", "kind", "kycStatus", "id"],
    users: ["fullName", "phone", "id", "inactiveAtUtcMs"],
    memberships: ["fullName", "orgId", "role", "roles"],
    vehicles: ["registrationNumber", "vehicleClass", "capacityKg", "orgId"],
    drivers: ["fullName", "userId", "orgId", "primaryVehicleId"],
    trips: [
      "id",
      "originCity",
      "destCity",
      "status",
      "capacityKg",
      "reservedKg",
    ],
    shipments: ["id", "customerOrgName", "status", "weightKg", "paymentReady"],
    ledger: ["id", "carrierId", "status", "netToCarrierPaise"],
    payouts: ["id", "createdAtUtcMs", "totalNetToCarrierPaise", "provider"],
  };
  const labels = {
    displayName: "Name",
    fullName: "Name",
    kycStatus: "Compliance",
    id: "ID",
    orgId: "Organization",
    userId: "User ID",
    roles: "Assigned roles",
    role: "Legacy role",
    originCity: "Origin",
    destCity: "Destination",
    weightKg: "Weight (kg)",
    capacityKg: "Capacity (kg)",
    reservedKg: "Reserved (kg)",
    paymentReady: "Ready for release",
    netToCarrierPaise: "Carrier amount (paise)",
    totalNetToCarrierPaise: "Total (paise)",
    createdAtUtcMs: "Created",
    inactiveAtUtcMs: "Inactive since",
  };
  preferred.members = ["fullName", "userId", "orgId", "role", "roles"];
  const columns = preferred[section];
  const t = document.createElement("table"),
    head = document.createElement("thead"),
    hr = document.createElement("tr");
  for (const key of [...columns, "Details"]) {
    const th = document.createElement("th");
    th.textContent = labels[key] || key;
    hr.append(th);
  }
  head.append(hr);
  t.append(head);
  const body = document.createElement("tbody");
  for (const row of out.items) {
    const tr = document.createElement("tr");
    for (const key of columns) {
      const td = document.createElement("td"),
        v = row[key];
      td.textContent =
        v == null
          ? "—"
          : key.endsWith("UtcMs")
            ? new Date(v).toLocaleString()
            : Array.isArray(v)
              ? v.join(", ")
              : String(v);
      tr.append(td);
    }
    const td = document.createElement("td"),
      b = document.createElement("button");
    b.textContent = "View";
    b.onclick = () => {
      $("record").textContent = JSON.stringify(row, null, 2);
      $("details").hidden = false;
      $("details").open = true;
    };
    td.append(b);
    tr.append(td);
    body.append(tr);
  }
  t.append(body);
  $("table").append(t);
}
$("search").onsubmit = perform(async () => {
  offset = 0;
  await table();
});
$("previous").onclick = perform(async () => {
  offset = Math.max(0, offset - 15);
  await table();
});
$("next").onclick = perform(async () => {
  offset += 15;
  await table();
});
function form(title, permission, description, fields, submit) {
  if (!can(permission)) return;
  const f = document.createElement("form");
  f.className = "card";
  const h = document.createElement("h3");
  h.textContent = title;
  f.append(h);
  const p = document.createElement("p");
  p.className = "muted";
  p.textContent = description;
  f.append(p);
  for (const [name, label, options] of fields) {
    const l = document.createElement("label"),
      input = document.createElement(options?.choices ? "select" : "input");
    input.name = name;
    input.id = "field-" + title.replaceAll(" ", "-") + "-" + name;
    l.htmlFor = input.id;
    l.textContent = label;
    if (options?.choices) {
      for (const v of options.choices) input.append(new Option(v, v));
    } else {
      input.type = options?.type || "text";
      if (options?.placeholder) input.placeholder = options.placeholder;
      if (options?.step) input.step = options.step;
    }
    input.required = !options?.optional;
    f.append(l, input);
  }
  const b = document.createElement("button");
  b.className = "primary";
  b.textContent = title;
  f.append(b);
  f.onsubmit = perform(async () => {
    if (saving) return;
    const data = Object.fromEntries(new FormData(f));
    if (
      !confirm(
        title +
          "? Review the target and values:\n" +
          JSON.stringify(data, null, 2),
      )
    )
      return;
    saving = true;
    b.disabled = true;
    try {
      const out = await submit(data, f);
      await load();
      $("notice").textContent =
        title +
        " completed. " +
        (out.org?.displayName
          ? out.org.displayName + " · " + out.org.id
          : out.shipment?.id || out.trip?.id || "");
    } finally {
      saving = false;
      b.disabled = false;
    }
  });
  $("actions").append(f);
}
function reasonHeaders(d) {
  return {
    "x-reason-code": d.reason,
    ...(d.effectiveActorId
      ? { "x-effective-actor-id": d.effectiveActorId }
      : {}),
  };
}
const reasonField = [
    "reason",
    "Reason code",
    { placeholder: "CUSTOMER_REQUEST" },
  ],
  actorField = ["effectiveActorId", "Represented member user ID"];
function actions() {
  $("actions").replaceChildren();
  form(
    "Set internal roles",
    "user.role_manage",
    "Creates or updates access in this internal organization. Enter the complete desired role set.",
    [
      ["userId", "Registered user ID"],
      [
        "roles",
        "Roles (comma separated)",
        { placeholder: "ADMIN,OPS,FINANCE" },
      ],
      reasonField,
    ],
    (d) =>
      request(
        "/v1/ops/dashboard-access",
        "POST",
        {
          userId: d.userId,
          roles: d.roles
            .split(",")
            .map((s) => s.trim())
            .filter(Boolean),
        },
        reasonHeaders(d),
      ),
  );
  form(
    "Set membership roles",
    "user.role_manage",
    "Replace roles on an existing membership. Empty roles revoke access.",
    [
      ["userId", "User ID"],
      ["orgId", "Target organization ID"],
      ["roles", "Roles (comma separated)", { optional: true }],
      reasonField,
    ],
    (d) =>
      request(
        "/v1/roles",
        "POST",
        {
          userId: d.userId,
          orgId: d.orgId,
          roles: d.roles
            .split(",")
            .map((s) => s.trim())
            .filter(Boolean),
        },
        reasonHeaders(d),
      ),
  );
  form(
    "Deactivate user",
    "user.role_manage",
    "Keeps audit history. Active work blocks deactivation unless Force is explicitly selected.",
    [
      ["userId", "User ID"],
      ["force", "Force active work", { choices: ["No", "Yes"] }],
      reasonField,
    ],
    (d) =>
      request(
        "/v1/ops/users/" +
          encodeURIComponent(d.userId) +
          (d.force === "Yes" ? "?force=1" : ""),
        "DELETE",
        undefined,
        reasonHeaders(d),
      ),
  );
  form(
    "Create carrier",
    "carrier.onboard",
    "Create a fleet organization for an existing active owner. Compliance remains NOT_STARTED.",
    [
      ["displayName", "Carrier name"],
      ["ownerUserId", "Existing owner user ID"],
      reasonField,
    ],
    (d, f) => {
      f.dataset.requestId ||= crypto.randomUUID();
      return request(
        "/v1/ops/carrier-organizations",
        "POST",
        {
          displayName: d.displayName,
          ownerUserId: d.ownerUserId,
          requestId: f.dataset.requestId,
        },
        reasonHeaders(d),
      );
    },
  );
  form(
    "Publish trip",
    "trip.publish",
    "Publish on behalf of a carrier member. Times must include the timezone.",
    [
      ["orgId", "Carrier organization ID"],
      actorField,
      ["originCity", "Origin city"],
      ["destCity", "Destination city"],
      ["windowStart", "Window start (ISO)"],
      ["windowEnd", "Window end (ISO)"],
      [
        "vehicleClass",
        "Vehicle class",
        { choices: ["SMALL", "MEDIUM", "LARGE"] },
      ],
      ["capacityKg", "Capacity (kg)", { type: "number" }],
      [
        "originLat",
        "Origin latitude",
        { type: "number", step: "any", optional: true },
      ],
      [
        "originLng",
        "Origin longitude",
        { type: "number", step: "any", optional: true },
      ],
      [
        "destLat",
        "Destination latitude",
        { type: "number", step: "any", optional: true },
      ],
      [
        "destLng",
        "Destination longitude",
        { type: "number", step: "any", optional: true },
      ],
      reasonField,
    ],
    (d) =>
      request(
        "/v1/pilot/anchor-trips",
        "POST",
        {
          ...d,
          capacityKg: Number(d.capacityKg),
          origin: point(d.originLat, d.originLng),
          destination: point(d.destLat, d.destLng),
        },
        reasonHeaders(d),
      ),
  );
  form(
    "Book shipment",
    "load.create",
    "Book for a customer member. The shipper completes checkout before carrier acceptance.",
    [
      ["customerOrgId", "Customer organization ID"],
      actorField,
      ["anchorTripId", "Anchor trip ID"],
      ["weightKg", "Weight (kg)", { type: "number" }],
      ["pickupAddress", "Pickup address"],
      ["dropAddress", "Drop address"],
      [
        "pickupLat",
        "Pickup latitude",
        { type: "number", step: "any", optional: true },
      ],
      [
        "pickupLng",
        "Pickup longitude",
        { type: "number", step: "any", optional: true },
      ],
      [
        "dropLat",
        "Drop latitude",
        { type: "number", step: "any", optional: true },
      ],
      [
        "dropLng",
        "Drop longitude",
        { type: "number", step: "any", optional: true },
      ],
      reasonField,
    ],
    (d) =>
      request(
        "/shipments/book",
        "POST",
        {
          ...d,
          weightKg: Number(d.weightKg),
          pickup: point(d.pickupLat, d.pickupLng),
          drop: point(d.dropLat, d.dropLng),
        },
        reasonHeaders(d),
      ),
  );
  form(
    "Submit POD",
    "pod.upload",
    "Submit for the assigned carrier. Shipper acceptance and Finance release remain separate.",
    [
      ["shipmentId", "Shipment ID"],
      actorField,
      ["notes", "Delivery notes", { optional: true }],
      reasonField,
    ],
    (d) =>
      request(
        "/shipments/" + encodeURIComponent(d.shipmentId) + "/driver-pod",
        "POST",
        { notes: d.notes },
        reasonHeaders(d),
      ),
  );
  form(
    "Release payment",
    "payment.capture",
    "Only eligible shipments: accepted POD or expired 48-hour hold.",
    [["shipmentId", "Shipment ID"], reasonField],
    (d) =>
      request(
        "/ops/shipments/" + encodeURIComponent(d.shipmentId) + "/release",
        "POST",
        {},
        reasonHeaders(d),
      ),
  );
  form(
    "Fail and refund",
    "payment.refund",
    "Refund an eligible failed shipment. This changes the shipment and payment state.",
    [["shipmentId", "Shipment ID"], reasonField],
    (d) =>
      request(
        "/shipments/" + encodeURIComponent(d.shipmentId) + "/fail-refund",
        "POST",
        {},
        reasonHeaders(d),
      ),
  );
  form(
    "Run payout batch",
    "settlement.release",
    "Processes eligible ledger lines in the configured payout mode. Inspect Payout batches for the current mode.",
    [reasonField],
    (d) => request("/payout-batches/run", "POST", {}, reasonHeaders(d)),
  );
  if (can("payment.read")) {
    const c = document.createElement("div");
    c.className = "card";
    const h = document.createElement("h3");
    h.textContent = "Payment queues";
    c.append(h);
    for (const [label, status] of [
      ["Pending release", "PENDING_RELEASE"],
      ["Recently delivered", "DELIVERED"],
    ]) {
      const b = document.createElement("button");
      b.textContent = label;
      b.onclick = perform(async () => {
        section = "shipments";
        offset = 0;
        $("status").value = status;
        $("query").value = "";
        await table();
        $("table-title").scrollIntoView({ behavior: "smooth" });
      });
      c.append(b);
    }
    $("actions").append(c);
  }
}
function point(lat, lng) {
  if (lat === "" && lng === "") return undefined;
  if (lat === "" || lng === "")
    throw Error("Provide both latitude and longitude.");
  return { lat: Number(lat), lng: Number(lng) };
}
async function queue() {
  const out = await request("/ops/compliance/pending");
  $("queue").replaceChildren();
  if (!out.organizations.length) {
    const p = document.createElement("p");
    p.textContent = "Every carrier is approved.";
    $("queue").append(p);
  }
  for (const o of out.organizations) {
    const row = document.createElement("div");
    row.className = "review-row";
    const detail = document.createElement("div"),
      name = document.createElement("strong"),
      status = document.createElement("small");
    name.textContent = o.displayName;
    status.textContent = o.kycStatus + " · " + o.id;
    detail.append(name, status);
    row.append(detail);
    for (const state of ["APPROVED", "REJECTED"]) {
      const b = document.createElement("button");
      b.textContent = state === "APPROVED" ? "Approve" : "Reject";
      b.onclick = perform(async () => {
        const reason = $("review-reason").value.trim();
        if (!/^[A-Z][A-Z0-9_]{2,63}$/.test(reason))
          throw Error(
            "Enter a reason code of 3–64 capitals, numbers or underscores.",
          );
        if (saving || !confirm(state + ": " + o.displayName + "?")) return;
        saving = true;
        const buttons = $("queue").querySelectorAll("button");
        buttons.forEach((x) => (x.disabled = true));
        try {
          await request(
            "/v1/organizations/" + encodeURIComponent(o.id) + "/kyc",
            "POST",
            { status: state },
            { "x-reason-code": reason },
          );
          await queue();
          $("notice").textContent =
            "Last review recorded: " + o.displayName + " is now " + state + ".";
          $("review-reason").value = "";
        } finally {
          saving = false;
          buttons.forEach((x) => (x.disabled = false));
        }
      });
      row.append(b);
    }
    $("queue").append(row);
  }
}
if (token) perform(load)();
`;
