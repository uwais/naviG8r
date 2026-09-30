/**
 * The redesigned operations page, served at /ops/beta beside the current /ops page until the team agrees
 * to switch. Like /ops it is a public shell: the API authorizes every request the page makes.
 * Built from the "NaviG8r ops console" design on the NaviG8r design system; token names match that system.
 *
 * Over 500 lines because it is one page: its styles, markup and script change together, and splitting
 * them would scatter one screen across files that are never read apart.
 */
export function opsConsoleBetaHtml(): string {
  return page;
}

// The website's logo file (apps/www/public/brand/logo-horizontal-light.svg), inlined because the API does
// not serve the website's files.
const logo = `<svg viewBox="0 0 1400 400" role="img" aria-label="NaviG8r" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="opsLogoBadge" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" stop-color="#16233D"/><stop offset="100%" stop-color="#0D1524"/></linearGradient></defs>
<g transform="translate(30, 60)"><rect x="0" y="0" width="280" height="280" rx="62" ry="62" fill="url(#opsLogoBadge)"/>
<path d="M 50 230 C 100 213, 126 165, 142 126" fill="none" stroke="#E8A33D" stroke-width="4" stroke-dasharray="1 10" stroke-linecap="round" opacity="0.55"/>
<circle cx="50" cy="230" r="7" fill="#E8A33D" opacity="0.55"/>
<g transform="translate(48,40) scale(7.7)" fill="#E8A33D" fill-rule="evenodd"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zM12 11.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></g></g>
<text x="360" y="248" font-family="Poppins" font-weight="700" font-size="132" fill="#131F35">Navi<tspan fill="#DC922C">G</tspan><tspan fill="#DC922C">8</tspan>r</text>
<text x="364" y="300" font-family="TeX Gyre Heros Cn" font-size="26" letter-spacing="6" fill="#5B6B87">FREIGHT &amp; LOGISTICS MARKETPLACE</text>
</svg>`;

const styles = `
:root{--navy:#16233d;--navy-ink:#131f35;--navy-deep:#0d1524;--slate:#5b6b87;--page:#f8f7f2;--card:#ffffff;--sunken:#f0eee6;
--line:#e4dfd3;--control-border:#8a8175;--ink:#2b2620;--on-navy:#ffffff;--focus:#16233d;--good:#1b6a35;--good-tint:#def0e2;
--attention:#845400;--attention-tint:#fcf0d4;--problem:#9b2c1f;--problem-tint:#f7e1dc;--info-tint:#e6e9ef;
--space-1:4px;--space-2:8px;--space-3:12px;--space-4:16px;--space-6:24px;
--radius-sm:8px;--radius-button:12px;--radius-input:14px;--radius-card:16px;--radius-pill:20px;
--font-display:"Poppins","Manrope",system-ui,sans-serif;--font-body:"Manrope",system-ui,-apple-system,"Segoe UI",sans-serif;
--font-mono:ui-monospace,"SF Mono",Menlo,Consolas,monospace;
/* Not in the design system yet: the dim layer behind the release confirmation (navy-deep at 45%). */
--scrim:rgba(13,21,36,0.45)}
*{box-sizing:border-box}
[hidden]{display:none!important}
body{margin:0;background:var(--page);color:var(--ink);font:400 15px/22px var(--font-body);font-variant-numeric:tabular-nums}
h1,h2{margin:0;font:600 18px/24px var(--font-display);color:var(--navy-ink)}
p{margin:0}
a{color:var(--navy);text-underline-offset:3px}
:focus-visible{outline:2px solid var(--focus);outline-offset:2px}
.visually-hidden{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap}
.caption{font-size:13px;line-height:18px;color:var(--slate)}
.field-label{font-size:13px;line-height:18px;font-weight:600;color:var(--ink)}
.id{font-family:var(--font-mono);font-size:13px;line-height:18px;color:var(--slate)}
.grow{flex-grow:1}
.stack{display:flex;flex-direction:column;gap:var(--space-1)}
.row{display:flex;align-items:flex-end;gap:var(--space-3);flex-wrap:wrap}
.row.top{align-items:flex-start}.row.center{align-items:center;gap:var(--space-2)}
header{background:var(--card);border-bottom:1px solid var(--line);padding:12px var(--space-4);display:flex;align-items:center;gap:var(--space-4);flex-wrap:wrap}
header svg{height:32px;width:auto;display:block}
.divider{width:1px;align-self:stretch;background:var(--line)}
.account{display:flex;align-items:center;gap:var(--space-3);flex-wrap:wrap}
.account .stack{gap:0}
.btn{font:600 15px/22px var(--font-body);border-radius:var(--radius-button);padding:8px 16px;min-height:40px;border:1px solid transparent;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;gap:var(--space-2);white-space:nowrap}
.btn-sm{font-size:13px;line-height:18px;padding:6px 12px;min-height:32px}
.btn-primary{background:var(--navy);color:var(--on-navy)}.btn-primary:hover{background:var(--navy-deep)}
.btn-secondary{background:var(--card);color:var(--navy);border-color:var(--control-border)}.btn-secondary:hover{background:var(--sunken)}
.btn-danger{background:var(--card);color:var(--problem);border-color:var(--problem)}.btn-danger:hover{background:var(--problem-tint)}
.btn-quiet{background:transparent;color:var(--navy);padding-left:8px;padding-right:8px}.btn-quiet:hover{background:var(--sunken)}
.btn[disabled]:not([aria-busy]){background:var(--sunken);color:var(--slate);border-color:transparent;cursor:not-allowed}
.btn[aria-busy]{cursor:progress}
.field{font:400 15px/22px var(--font-body);color:var(--ink);background:var(--card);border:1px solid var(--control-border);border-radius:var(--radius-input);padding:8px 12px;min-height:40px;width:100%}
.field.mono{font-family:var(--font-mono);font-size:13px}
.field[aria-invalid=true]{border:2px solid var(--problem);padding:7px 11px}
.field[readonly]{background:var(--sunken);border-color:transparent}
select.field{width:auto;min-height:32px;padding:4px 8px;font-weight:600}
.reason{width:320px;max-width:100%}
.tag{display:inline-flex;align-items:center;gap:6px;border-radius:var(--radius-sm);padding:2px 8px;font-size:13px;line-height:18px;font-weight:600}
.tag svg{width:12px;height:12px;flex-shrink:0;fill:none;stroke:currentColor;stroke-width:3;stroke-linecap:round;stroke-linejoin:round}
.tag-good{background:var(--good-tint);color:var(--good)}.tag-attention{background:var(--attention-tint);color:var(--attention)}
.tag-problem{background:var(--problem-tint);color:var(--problem)}.tag-info{background:var(--info-tint);color:var(--navy)}
.role{display:inline-flex;border:1px solid var(--control-border);border-radius:var(--radius-sm);padding:1px 7px;font-size:13px;line-height:18px;font-weight:600;background:var(--card)}
.card{background:var(--card);border:1px solid var(--line);border-radius:var(--radius-card)}
.msg{border-radius:var(--radius-sm);padding:8px 12px;font-size:13px;line-height:18px;display:flex;gap:var(--space-2);align-items:flex-start}
.msg-err{background:var(--problem-tint);color:var(--problem)}.msg-ok{background:var(--good-tint);color:var(--good)}.msg-info{background:var(--info-tint);color:var(--navy)}
.spin{width:14px;height:14px;flex-shrink:0;border-radius:7px;border:2px solid currentColor;border-right-color:transparent;animation:spin .8s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
@media (prefers-reduced-motion:reduce){.spin{animation:none}}
.tools{padding:var(--space-4) var(--space-4) 0;display:flex;align-items:center;gap:var(--space-2);flex-wrap:wrap}
.jump{display:inline-flex;align-items:center;gap:var(--space-2);padding:6px 12px;border-radius:var(--radius-pill);background:var(--card);border:1px solid var(--control-border);color:var(--navy);font-weight:600;font-size:13px;line-height:18px;text-decoration:none}
.jump:hover{background:var(--sunken)}
.count{min-width:20px;text-align:center;padding:0 6px;border-radius:10px;background:var(--navy);color:var(--on-navy);line-height:20px;font-weight:700}
.legend{display:flex;align-items:center;gap:var(--space-2);flex-wrap:wrap}
.notice{margin:var(--space-6) var(--space-4) 0;padding:var(--space-4);display:flex;flex-direction:column;gap:var(--space-2)}
main{padding:var(--space-6) var(--space-4) var(--space-4);display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:var(--space-6) var(--space-4);align-items:start}
.span2{grid-column:span 2}.span3{grid-column:span 3}
@media (max-width:1100px){main{grid-template-columns:minmax(0,1fr)}.span2,.span3{grid-column:auto}}
section.card{display:flex;flex-direction:column;overflow:hidden}
.head{display:flex;align-items:center;gap:var(--space-3);padding:var(--space-4);border-bottom:1px solid var(--line)}
.body{padding:var(--space-4);display:flex;flex-direction:column;gap:var(--space-3)}
article{padding:var(--space-4);display:flex;flex-direction:column;gap:var(--space-3)}
article+article{border-top:1px solid var(--line)}
.scroll{overflow-x:auto}
table{border-collapse:collapse;width:100%}
th{background:var(--sunken);text-align:left;font-size:13px;line-height:18px;font-weight:600;padding:8px 16px}
td{border-top:1px solid var(--line);padding:12px 16px;vertical-align:top}
td .id{white-space:nowrap}
td .id:first-child{font-weight:600;color:var(--ink)}
.num{text-align:right;font-weight:600}
fieldset{border:0;margin:0;padding:0;display:flex;flex-direction:column;gap:var(--space-2)}
legend{padding:0;margin-bottom:var(--space-2)}
.choice{display:inline-flex;align-items:center;gap:var(--space-2);margin-right:var(--space-6)}
.choice input{width:18px;height:18px;margin:0;accent-color:var(--navy)}
dialog{border:0;border-radius:var(--radius-card);padding:var(--space-6);width:min(480px,calc(100vw - 32px));background:var(--card);color:var(--ink)}
dialog[open]{display:flex;flex-direction:column;gap:var(--space-4)}
dialog::backdrop{background:var(--scrim)}
.money{background:var(--sunken);border-radius:var(--radius-button);padding:4px 16px}
.money div{display:flex;justify-content:space-between;padding:8px 0}
.money div+div{border-top:1px solid var(--line)}
.money .total{font-weight:700}
.pair{display:grid;grid-template-columns:1fr 1fr;gap:var(--space-3)}
#signin{max-width:400px;margin:48px auto;padding:var(--space-6);display:flex;flex-direction:column;gap:var(--space-3)}
#pageMessage:empty,#byIdOff:empty{display:none}
#pageMessage{margin:var(--space-4) var(--space-4) 0}
footer{padding:var(--space-4);border-top:1px solid var(--line);display:flex;gap:var(--space-4);flex-wrap:wrap}
`;

const markup = `
<header>
  ${logo}
  <div class="divider"></div>
  <h1>Operations</h1>
  <div class="grow"></div>
  <div id="account" class="account" hidden>
    <div class="stack">
      <span class="caption">Signed in as <strong id="userName"></strong></span>
      <span class="caption row center">Your roles <span id="roleChips" class="row center"></span></span>
    </div>
    <div class="divider"></div>
    <label class="stack"><span class="caption">Acting for</span><select id="organization" class="field"></select></label>
    <button id="signout" class="btn btn-secondary btn-sm" type="button">Sign out</button>
  </div>
</header>
<div id="pageMessage"></div>
<section id="signin" class="card" aria-labelledby="signinTitle" hidden>
  <h2 id="signinTitle">Sign in</h2>
  <label class="stack"><span class="field-label">Phone</span><input id="phone" class="field" autocomplete="tel" inputmode="tel"></label>
  <div><button id="start" class="btn btn-secondary" type="button">Send code</button></div>
  <label class="stack"><span class="field-label">Verification code</span><input id="code" class="field" autocomplete="one-time-code" inputmode="numeric"></label>
  <div><button id="verify" class="btn btn-primary" type="button">Sign in</button></div>
  <div id="signinResult"></div>
</section>
<div id="workspace" hidden>
  <div id="notice" class="card notice" hidden><p id="noticeText"></p><p id="noticeHelp" class="caption"></p></div>
  <div id="tools" class="tools" hidden>
    <span class="caption">Needs someone</span>
    <a class="jump" href="#carriers" id="jumpCarriers">Carriers waiting <span class="count" id="countCarriers">0</span></a>
    <a class="jump" href="#payments">Payments waiting <span class="count" id="countPayments">0</span></a>
    <a class="jump" href="#team">Team access</a>
    <div class="grow"></div>
    <div id="legend" class="legend" role="group" aria-label="Status key"><span class="caption">Status key</span></div>
  </div>
  <main id="sections" hidden>
    <section id="carriers" class="card span2" aria-labelledby="carriersTitle">
      <div class="head"><h2 id="carriersTitle">Carriers waiting for approval</h2><span id="carriersCount" class="caption"></span><div class="grow"></div><span id="carriersUpdated" class="caption"></span><button id="carriersReload" class="btn btn-quiet btn-sm" type="button">Reload</button></div>
      <div id="carriersBody"></div>
    </section>
    <section id="byId" class="card" aria-labelledby="byIdTitle">
      <div class="head"><h2 id="byIdTitle">Review any carrier by ID</h2></div>
      <form id="byIdForm" class="body" novalidate>
        <p class="caption">For carriers not in the list, such as taking back an approval. The change and your reason are kept in the carrier's history.</p>
        <div id="byIdOff"></div>
        <label class="stack"><span class="field-label">Carrier ID</span><input id="byIdCarrier" class="field mono" autocomplete="off" spellcheck="false"></label>
        <fieldset><legend class="field-label">Decision</legend>
          <div><label class="choice"><input type="radio" name="decision" value="APPROVED">Approve</label><label class="choice"><input type="radio" name="decision" value="REJECTED">Reject</label></div>
          <span class="caption">Nothing is chosen for you. Pick one.</span></fieldset>
        <label class="stack"><span class="field-label">Reason code</span><input id="byIdReason" class="field mono" autocomplete="off" spellcheck="false" aria-describedby="byIdHelp"></label>
        <span id="byIdHelp" class="caption">3 to 64 capitals, numbers or underscores, starting with a letter.</span>
        <div><button class="btn btn-primary" type="submit">Record review</button></div>
        <div id="byIdResult"></div>
      </form>
    </section>
    <section id="payments" class="card span3" aria-labelledby="paymentsTitle">
      <div class="head"><h2 id="paymentsTitle">Payments waiting for release</h2><span id="paymentsCount" class="caption"></span><div class="grow"></div><span id="paymentsUpdated" class="caption"></span><button id="paymentsReload" class="btn btn-quiet btn-sm" type="button">Reload</button></div>
      <div id="paymentsBody"></div>
    </section>
    <section id="team" class="card" aria-labelledby="teamTitle">
      <div class="head"><h2 id="teamTitle">Team access</h2><div class="grow"></div><span id="teamTag"></span></div>
      <div id="teamBody" class="body"></div>
    </section>
  </main>
</div>
<dialog id="release" aria-labelledby="releaseTitle" aria-describedby="releaseText">
  <h2 id="releaseTitle"></h2>
  <p id="releaseText"></p>
  <div id="releaseMoney" class="money"></div>
  <div id="releaseResult"></div>
  <div class="pair"><button id="releaseCancel" class="btn btn-secondary" type="button">Cancel</button><button id="releaseConfirm" class="btn btn-primary" type="button"></button></div>
</dialog>
<footer class="caption"><span>NaviG8r operations</span><span>All times IST, 24-hour</span><span>This is the beta page. The current page is still at <a href="/ops">/ops</a>.</span></footer>
`;

// Browser code. Every name or ID from the server goes in through textContent, never as HTML.
const script = `
const byId = id => document.getElementById(id);
let token = sessionStorage.getItem('navig8r_access') || '';
let org = sessionStorage.getItem('navig8r_org') || '';
let challenge = '', me = null, principal = null, releasing = null, releaseBusy = false;
// Matches what the server keeps in the audit record; a code that fails this is silently dropped there.
const reasonPattern = /^[A-Z][A-Z0-9_]{2,63}$/;
const reasonRule = '3 to 64 capitals, numbers or underscores, starting with a letter, for example DOCUMENTS_REVIEWED';
const pageSize = 20;
const loadedAt = {};

function element(tag, props, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props || {})) {
    if (value === undefined || value === null || value === false) continue;
    if (key === 'class') node.className = value;
    else if (key === 'text') node.textContent = value;
    else if (key.startsWith('on')) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value === true ? '' : value);
  }
  for (const child of children.flat()) if (child !== null && child !== undefined && child !== false) node.append(child);
  return node;
}

const timeIST = ms => new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kolkata', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(ms) + ' IST';
function dateIST(ms, withYear = true) {
  const part = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Kolkata', day: 'numeric', month: 'short', year: 'numeric' }).formatToParts(ms).map(piece => [piece.type, piece.value]));
  return part.day + ' ' + part.month + (withYear ? ' ' + part.year : '');
}
const rupees = paise => '₹' + (paise / 100).toLocaleString('en-IN', { minimumFractionDigits: paise % 100 ? 2 : 0, maximumFractionDigits: 2 });
const plural = (count, word) => count + ' ' + word + (count === 1 ? '' : 's');
const inWords = list => list.length < 2 ? list.join('') : list.slice(0, -1).join(', ') + ' and ' + list[list.length - 1];
const can = permission => !!principal && principal.permissions.includes(permission);

const errorWords = {
  unauthorized: 'your session has ended, so sign in again',
  forbidden: "your role doesn't allow this",
  not_found: "that wasn't found",
  self_verification_forbidden: "you can't review your own organization",
  payment_hold_active: 'the payment is still on hold',
  invalid_role: "one of those roles doesn't fit that organization",
  verification_status_and_reason_required: 'a decision and a reason code are both needed',
  otp_incorrect: 'that code is wrong, so check it and try again',
  otp_expired: 'that code has expired, so send a new one',
  otp_challenge_invalid: "that code request isn't valid any more, so send a new code",
  otp_challenge_mismatch: "that code request isn't valid any more, so send a new code",
  otp_challenge_not_found: "that code request isn't valid any more, so send a new code",
  shipment_not_pending_release: 'this shipment is no longer waiting for release, so someone may have released it already',
  checkout_not_completed_for_pod: "the shipper hasn't finished paying for this shipment",
  payment_not_captured: "the shipper's payment hasn't been collected",
  shipment_not_found: "that shipment wasn't found",
  payment_not_found: 'this shipment has no payment record the server can use',
  payment_id_missing: 'this shipment has no payment record the server can use',
  invalid_organization: "the organization you're acting for isn't valid",
  account_inactive: 'this account is switched off',
  internal_error: 'the server hit an error',
  bad_request: "the server couldn't read the request",
};
// The server refuses with these before it changes anything. Any other error may come after a change was
// made and not saved, so the page must not say nothing happened.
const refusedBeforeChange = ['unauthorized', 'forbidden', 'not_found', 'self_verification_forbidden', 'verification_status_and_reason_required',
  'invalid_role', 'payment_hold_active', 'shipment_not_found', 'payment_not_found', 'payment_id_missing', 'checkout_not_completed_for_pod', 'shipment_not_pending_release'];
async function request(path, method = 'GET', body, headers = {}) {
  const sent = { 'content-type': 'application/json', ...headers };
  if (token) sent.authorization = 'Bearer ' + token;
  if (org) sent['x-organization-id'] = org;
  let response;
  try { response = await fetch(path, { method, headers: sent, body: body === undefined ? undefined : JSON.stringify(body) }); }
  catch { throw Object.assign(Error("the server didn't respond"), { answered: false, unchanged: false }); }
  const out = await response.json().catch(() => ({}));
  const code = out.error || String(response.status);
  if (response.status === 401) byId('signin').hidden = false;
  if (!response.ok) throw Object.assign(Error(errorWords[code] || "the server gave an error this page doesn't recognise (" + code + ')'), { answered: true, unchanged: refusedBeforeChange.includes(code) });
  return out;
}
const nothingChanged = error => error.unchanged ? 'Nothing changed.' : "Couldn't confirm whether it was saved. Reload to see the current status before trying again.";

const shapes = {
  good: '<path d="M5 12l5 5L20 7"/>',
  attention: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  problem: '<circle cx="12" cy="12" r="9"/><path d="M12 7v6M12 16.5v.5"/>',
  info: '<path d="M5 12h14M13 6l6 6-6 6"/>',
};
function statusTag([words, kind]) {
  const tag = element('span', { class: 'tag tag-' + kind });
  tag.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true">' + shapes[kind] + '</svg>';
  tag.append(words);
  return tag;
}
const carrierWords = { SUBMITTED: ['Bank details submitted', 'attention'], NOT_STARTED: ['No bank details yet', 'problem'], REJECTED: ['Not approved', 'problem'], APPROVED: ['Approved', 'good'] };
const carrierStatus = code => carrierWords[code] || ['Status not recognised', 'problem'];
const kindWords = { CARRIER_FLEET: 'Fleet', CARRIER_SOLO: 'Owner-operator', CARRIER_LEGACY: 'Carrier' };
function paymentStatus(shipment) {
  if (shipment.paymentReady) return ['Ready for payment release', 'attention'];
  if (shipment.podAtUtcMs && shipment.paymentHoldUntilUtcMs) return ['Payment held until the shipper accepts or ' + dateIST(shipment.paymentHoldUntilUtcMs, false), 'info'];
  return ['Waiting for proof of delivery', 'info'];
}

function message(kind, text) { return element('div', { class: 'msg msg-' + kind, role: kind === 'err' ? 'alert' : 'status' }, element('span', { text })); }
const note = text => element('div', { class: 'msg msg-info' }, element('span', { text }));
const roleChip = role => element('span', { class: 'role', text: role });
function busy(button, words) { button.dataset.label = button.textContent; button.setAttribute('aria-busy', 'true'); button.replaceChildren(element('span', { class: 'spin', 'aria-hidden': 'true' }), words); }
function idle(button) { button.removeAttribute('aria-busy'); button.textContent = button.dataset.label; }
async function run(action, failure, place = byId('pageMessage')) {
  place.replaceChildren();
  try { await action(); } catch (error) { place.replaceChildren(message('err', failure + ': ' + error.message + '.')); }
}

function sectionLoading(name, what) {
  byId(name + 'Body').replaceChildren(element('div', { class: 'body' }, element('div', { class: 'msg msg-info', role: 'status' }, element('span', { class: 'spin', 'aria-hidden': 'true' }), element('span', { text: 'Loading ' + what + '…' }))));
}
function sectionFailed(name, what, error, reload) {
  const last = loadedAt[name] ? ' Last loaded ' + timeIST(loadedAt[name]) + '.' : '';
  const reason = error.answered ? ': ' + error.message + '.' : '. Check your connection, then reload.';
  byId(name + 'Body').replaceChildren(element('div', { class: 'body' }, message('err', "Couldn't load " + what + reason + last), element('div', {}, element('button', { class: 'btn btn-secondary btn-sm', type: 'button', text: 'Reload', onclick: reload }))));
}
function sectionLoaded(name) { loadedAt[name] = Date.now(); byId(name + 'Updated').textContent = 'Updated ' + timeIST(loadedAt[name]); }
function pages(total, describe, addNext) {
  const text = element('p'), button = element('button', { class: 'btn btn-secondary btn-sm', type: 'button', text: 'Show 20 more' });
  const more = element('div', { class: 'body' }, text, element('div', {}, button));
  const showNext = () => { const shown = addNext(); text.textContent = 'Showing ' + shown + ' of ' + total + '. ' + describe; more.hidden = shown >= total; button.textContent = 'Show ' + Math.min(pageSize, total - shown) + ' more'; };
  button.onclick = showNext;
  showNext();
  return more;
}

let carriers = [];
async function loadCarriers() {
  const allowed = can('kyc.verify'), onlyOps = 'Only OPS can review carriers. You hold ' + inWords(principal.roles) + '.';
  byId('carriersReload').hidden = byId('jumpCarriers').hidden = !allowed;
  byId('byIdOff').replaceChildren(allowed ? '' : note(onlyOps));
  for (const control of byId('byIdForm').elements) control.disabled = !allowed;
  if (!allowed) {
    byId('carriersCount').textContent = byId('carriersUpdated').textContent = '';
    byId('carriersBody').replaceChildren(element('div', { class: 'body' }, note(onlyOps)));
    return;
  }
  byId('countCarriers').textContent = '–';
  sectionLoading('carriers', 'carriers waiting for approval');
  try { carriers = (await request('/ops/compliance/pending')).organizations; }
  catch (error) { byId('carriersCount').textContent = ''; sectionFailed('carriers', 'carriers waiting for approval', error, loadCarriers); return; }
  sectionLoaded('carriers');
  byId('carriersCount').textContent = plural(carriers.length, 'carrier');
  byId('countCarriers').textContent = carriers.length;
  if (!carriers.length) {
    byId('carriersBody').replaceChildren(element('div', { class: 'body' }, element('p', { text: 'No carriers are waiting for approval.' }), element('p', { class: 'caption', text: 'Carriers appear here after they sign up.' })));
    return;
  }
  const list = element('div');
  const more = pages(carriers.length, 'Bank details submitted first, then no bank details, then not approved; oldest first within each.', () => {
    list.append(...carriers.slice(list.children.length, list.children.length + pageSize).map(carrierCard));
    return list.children.length;
  });
  byId('carriersBody').replaceChildren(list, more);
}

function carrierCard(carrier) {
  const name = carrier.displayName, inputId = 'reason-' + carrier.id, helpId = inputId + '-help', ownId = inputId + '-own';
  const own = me.organizations.some(organization => organization.id === carrier.id);
  const status = element('span', {}, statusTag(carrierStatus(carrier.kycStatus)));
  const input = element('input', { id: inputId, class: 'field mono', autocomplete: 'off', spellcheck: 'false', 'aria-describedby': helpId });
  const approve = element('button', { class: 'btn btn-primary', type: 'button', text: 'Approve' });
  const reject = element('button', { class: 'btn btn-danger', type: 'button', text: 'Reject' });
  const result = element('div', { id: inputId + '-result' });
  const meta = [kindWords[carrier.kind], 'joined ' + dateIST(carrier.createdAtUtcMs)].filter(Boolean).join(' · ');
  if (own) for (const button of [approve, reject]) { button.disabled = true; button.setAttribute('aria-describedby', ownId); }
  const review = (decision, button) => recordReview({ carrier, decision, input, button, result, status, locks: [approve, reject] });
  approve.onclick = () => review('APPROVED', approve);
  reject.onclick = () => review('REJECTED', reject);
  return element('article', { 'aria-label': name + ' (' + carrier.id + ')' },
    element('div', { class: 'row top' },
      element('div', { class: 'stack grow' }, element('div', { class: 'row center' }, element('strong', { text: name }), element('span', { class: 'id', text: carrier.id })), element('span', { class: 'caption', text: meta })),
      status),
    element('div', { class: 'row' },
      element('label', { class: 'stack reason' }, element('span', { class: 'field-label' }, 'Reason code', element('span', { class: 'visually-hidden', text: ' for ' + name + ' (' + carrier.id + ')' })), input),
      approve, element('div', { class: 'grow' }), reject),
    element('span', { id: helpId, class: 'caption', text: '3 to 64 capitals, numbers or underscores, starting with a letter. Needed for both Approve and Reject.' }),
    own ? element('span', { id: ownId, class: 'caption', text: "You can't review your own organization. Ask another teammate with OPS." }) : null,
    result);
}

async function recordReview({ carrier, decision, input, button, result, status, locks }) {
  const approving = decision === 'APPROVED', code = input.value.trim();
  result.replaceChildren();
  if (!reasonPattern.test(code)) {
    input.setAttribute('aria-invalid', 'true');
    result.append(message('err', (approving ? 'Not approved yet. ' : 'Not rejected yet. ') + 'Reason code must be ' + reasonRule + '. What you typed is kept above.'));
    input.focus();
    return;
  }
  input.removeAttribute('aria-invalid');
  const unlocked = [...document.querySelectorAll('#carriers button, #byIdForm button')].filter(button => !button.disabled);
  unlocked.forEach(button => { button.disabled = true; });
  busy(button, approving ? 'Approving…' : 'Rejecting…');
  try {
    const out = await request('/v1/organizations/' + encodeURIComponent(carrier.id) + '/kyc', 'POST', { status: decision }, { 'x-reason-code': code });
    idle(button);
    unlocked.filter(button => !locks.includes(button)).forEach(button => { button.disabled = false; });
    input.readOnly = true;
    locks.forEach(button => button.setAttribute('aria-describedby', result.id));
    status.replaceChildren(statusTag(carrierStatus(out.org.kycStatus)));
    const by = ' by you at ' + timeIST(Date.now()) + ' with ' + code + '. ';
    const change = ' To change this decision, use Review any carrier by ID.';
    result.append(message('ok', approving
      ? 'Approved' + by + out.org.displayName + ' can now accept shipments. It leaves this list on the next reload.' + change
      : 'Not approved' + by + out.org.displayName + " can't accept shipments until it is approved." + change));
  } catch (error) {
    idle(button);
    unlocked.forEach(button => { button.disabled = false; });
    result.append(message('err', "Couldn't save the review: " + error.message + '. ' + nothingChanged(error) + ' Your reason code is kept.'));
  }
}

byId('byIdForm').onsubmit = async event => {
  event.preventDefault();
  const result = byId('byIdResult'), button = byId('byIdForm').querySelector('button'), idInput = byId('byIdCarrier'), reasonInput = byId('byIdReason');
  const carrierId = idInput.value.trim(), code = reasonInput.value.trim(), picked = document.querySelector('input[name=decision]:checked');
  result.replaceChildren();
  reasonInput.removeAttribute('aria-invalid');
  const problem = !carrierId ? ['Type the carrier ID.', idInput] : !picked ? ['Pick Approve or Reject.', document.querySelector('input[name=decision]')]
    : !reasonPattern.test(code) ? ['Reason code must be ' + reasonRule + '.', reasonInput] : null;
  if (problem) {
    if (problem[1] === reasonInput) reasonInput.setAttribute('aria-invalid', 'true');
    result.append(message('err', 'Not recorded yet. ' + problem[0]));
    problem[1].focus();
    return;
  }
  const unlocked = [...document.querySelectorAll('#carriers button, #byIdForm button')].filter(button => !button.disabled);
  unlocked.forEach(button => { button.disabled = true; });
  busy(button, 'Recording…');
  try {
    const out = await request('/v1/organizations/' + encodeURIComponent(carrierId) + '/kyc', 'POST', { status: picked.value }, { 'x-reason-code': code });
    result.append(message('ok', 'Review recorded by you at ' + timeIST(Date.now()) + ' with ' + code + '. ' + out.org.displayName + ' (' + out.org.id + ') now shows: ' + carrierStatus(out.org.kycStatus)[0] + '.'));
    idInput.value = reasonInput.value = '';
    picked.checked = false;
    await loadCarriers();
  } catch (error) {
    result.append(message('err', "Couldn't record the review: " + error.message + '. ' + nothingChanged(error)));
  } finally {
    idle(button);
    unlocked.forEach(button => { if (button.isConnected) button.disabled = false; });
  }
};

let payments = [];
async function loadPayments() {
  byId('countPayments').textContent = '–';
  sectionLoading('payments', 'payments waiting for release');
  try { payments = (await request('/ops/shipments/pending-release')).shipments; }
  catch (error) { byId('paymentsCount').textContent = ''; sectionFailed('payments', 'payments waiting for release', error, loadPayments); return; }
  sectionLoaded('payments');
  payments.sort((first, second) => (first.podAtUtcMs ?? Infinity) - (second.podAtUtcMs ?? Infinity));
  byId('paymentsCount').textContent = plural(payments.length, 'shipment');
  byId('countPayments').textContent = payments.length;
  if (!payments.length) {
    byId('paymentsBody').replaceChildren(element('div', { class: 'body' }, element('p', { text: 'No payments are waiting for release.' }), element('p', { class: 'caption', text: 'Shipments appear here after the driver uploads proof of delivery.' })));
    return;
  }
  const showAmounts = payments.some(shipment => Number.isFinite(shipment.netToCarrierPaise));
  const headings = ['Shipment', 'Carrier', 'Status', 'Proof of delivery', ...(showAmounts ? ['Carrier receives'] : []), 'Action'];
  const rows = element('tbody');
  const more = pages(payments.length, 'Oldest proof of delivery first.', () => {
    rows.append(...payments.slice(rows.children.length, rows.children.length + pageSize).map(shipment => paymentRow(shipment, showAmounts)));
    return rows.children.length;
  });
  byId('paymentsBody').replaceChildren(...[
    element('div', { class: 'scroll' }, element('table', {}, element('thead', {}, element('tr', {}, headings.map(heading => element('th', { scope: 'col', class: heading === 'Carrier receives' ? 'num' : null, text: heading })))), rows)),
    showAmounts ? null : element('p', { class: 'caption body', text: 'Amounts are shown to FINANCE only.' }),
    more].filter(Boolean));
}

function paymentRow(shipment, showAmounts) {
  const at = ms => dateIST(ms, false) + ', ' + timeIST(ms);
  const route = shipment.pickupAddress && shipment.dropAddress ? shipment.pickupAddress + ' to ' + shipment.dropAddress : null;
  const status = element('td', {}, statusTag(paymentStatus(shipment)));
  const proof = shipment.podAtUtcMs
    ? element('td', {}, 'Uploaded ' + at(shipment.podAtUtcMs), element('div', { class: 'caption', text: shipment.podAcceptedAtUtcMs ? 'Shipper accepted ' + at(shipment.podAcceptedAtUtcMs) : 'Shipper has not accepted yet' }))
    : element('td', {}, element('span', { class: 'caption', text: 'Not uploaded yet' }));
  const action = element('td');
  const whyId = 'why-' + shipment.id;
  const off = reason => action.append(element('button', { class: 'btn btn-sm', type: 'button', disabled: true, 'aria-describedby': whyId, text: 'Release payment' }), element('div', { id: whyId, class: 'caption', text: reason }));
  if (!can('payment.capture')) off('Only FINANCE can release payments. You hold ' + inWords(principal.roles) + '.');
  else if (!shipment.paymentReady) off(shipment.podAtUtcMs ? 'Hold ends ' + at(shipment.paymentHoldUntilUtcMs) : 'Needs proof of delivery first');
  else {
    const result = element('div');
    const button = element('button', { class: 'btn btn-primary btn-sm', type: 'button', text: 'Release payment…' });
    button.onclick = () => openRelease({ shipment, trigger: button, result, status, action });
    action.append(button, result);
  }
  return element('tr', {},
    element('td', {}, element('span', { class: 'id', text: shipment.id }), route ? element('div', { class: 'caption', text: route }) : null),
    element('td', {}, element('span', { class: 'id', text: shipment.carrierId })),
    status, proof,
    showAmounts ? element('td', { class: 'num', text: Number.isFinite(shipment.netToCarrierPaise) ? rupees(shipment.netToCarrierPaise) : '' }) : null,
    action);
}

const moneyLine = (label, amount, total) => element('div', { class: total ? 'total' : null }, element('span', { text: label }), element('span', { text: amount }));
// One release opens at a time, so a slow reply can never swap another shipment into an open dialog.
let openingRelease = false;
async function openRelease(row) {
  if (openingRelease || byId('release').open) return;
  openingRelease = true;
  row.result.replaceChildren();
  busy(row.trigger, 'Opening…');
  row.trigger.disabled = true;
  let detail;
  try { detail = await request('/ops/shipments/' + encodeURIComponent(row.shipment.id)); }
  catch (error) { row.result.append(message('err', "Couldn't open the release: " + error.message + '. Nothing was paid.')); return; }
  finally { idle(row.trigger); row.trigger.disabled = false; openingRelease = false; }
  if (!row.trigger.isConnected) return;
  const fresh = detail.shipment, amounts = [fresh.grossPaise, fresh.commissionPaise, fresh.netToCarrierPaise];
  if (fresh.status !== 'PENDING_RELEASE' || !fresh.paymentReady) {
    row.result.append(message('err', 'This shipment is no longer ready for release. Someone may have released it already. Reload the list to see where it stands. Nothing was paid.'));
    return;
  }
  if (!amounts.every(Number.isFinite)) {
    row.result.append(message('err', "Release is off for this shipment: the server didn't send all three amounts (shipper paid, commission, carrier receives)."));
    return;
  }
  const [gross, commission, net] = amounts, otherFees = gross - commission - net;
  byId('releaseTitle').textContent = 'Release payment for shipment ' + fresh.id + '?';
  byId('releaseText').replaceChildren(detail.carrierOrgName + ' ', element('span', { class: 'id', text: fresh.carrierId }), ' is owed ' + rupees(net) + ". It goes out in a weekly payout batch to the bank account on file; if there is none yet, it waits until one is added. This can't be undone from the console.");
  byId('releaseMoney').replaceChildren(...[
    moneyLine('Shipper paid', rupees(gross)),
    moneyLine('NaviG8r commission', '− ' + rupees(commission)),
    otherFees ? moneyLine('Other fees and adjustments', (otherFees > 0 ? '− ' : '+ ') + rupees(Math.abs(otherFees))) : null,
    moneyLine('Carrier receives', rupees(net), true)].filter(Boolean));
  byId('releaseConfirm').textContent = 'Release ' + rupees(net);
  byId('releaseResult').replaceChildren();
  releasing = row;
  byId('release').showModal();
  byId('releaseCancel').focus();
}
function closeRelease() {
  if (releaseBusy) return;
  const row = releasing;
  releasing = null;
  byId('release').close();
  if (row && row.trigger.isConnected) row.trigger.focus();
}
byId('releaseCancel').onclick = closeRelease;
byId('release').addEventListener('cancel', event => { event.preventDefault(); closeRelease(); });
// Close on the dim background only when the press started there too, so selecting text never closes it.
function onBackdrop(event) {
  const box = byId('release').getBoundingClientRect();
  return event.target === byId('release') && (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom);
}
let pressedOnBackdrop = false;
byId('release').addEventListener('mousedown', event => { pressedOnBackdrop = onBackdrop(event); });
byId('release').addEventListener('click', event => { if (pressedOnBackdrop && onBackdrop(event)) closeRelease(); pressedOnBackdrop = false; });
byId('releaseConfirm').onclick = async () => {
  const row = releasing, confirm = byId('releaseConfirm'), cancel = byId('releaseCancel');
  if (!row) return;
  byId('releaseResult').replaceChildren();
  busy(confirm, 'Releasing…');
  confirm.disabled = cancel.disabled = releaseBusy = true;
  try {
    await request('/ops/shipments/' + encodeURIComponent(row.shipment.id) + '/release', 'POST', {});
    const done = message('ok', 'Payment released by you at ' + timeIST(Date.now()) + '. The carrier is paid in a weekly payout batch.');
    done.tabIndex = -1;
    row.status.replaceChildren(statusTag(['Payment released', 'good']));
    row.action.replaceChildren(done);
    releaseBusy = false;
    releasing = null;
    byId('release').close();
    done.focus();
  } catch (error) {
    releaseBusy = false;
    byId('releaseResult').replaceChildren(message('err', "Couldn't release the payment: " + error.message + '. ' + (error.unchanged ? 'Nothing was paid by this attempt.' : 'It may or may not have gone through. Cancel, reload the list and check before trying again.')));
  } finally {
    idle(confirm);
    confirm.disabled = cancel.disabled = false;
  }
};

function renderTeam() {
  const admin = can('user.role_manage');
  byId('teamTag').replaceChildren(admin ? '' : element('span', { class: 'tag tag-info', text: 'Read only' }));
  const yours = element('div', { class: 'stack' }, element('span', { class: 'field-label', text: 'Your roles' }), element('div', { class: 'row center' }, principal.roles.map(roleChip)));
  const explain = element('p', { class: 'caption', text: 'OPS approves carriers. FINANCE releases payments. ADMIN manages roles.' });
  if (!admin) byId('teamBody').replaceChildren(note('Only someone with the ADMIN role can give or remove roles. You hold ' + inWords(principal.roles) + '.'), yours, explain);
  else byId('teamBody').replaceChildren(yours, explain, roleForm());
}

function roleForm() {
  const user = element('input', { class: 'field mono', autocomplete: 'off', spellcheck: 'false' });
  const organization = element('input', { class: 'field mono', autocomplete: 'off', spellcheck: 'false' });
  const boxes = ['OPS', 'FINANCE', 'ADMIN', 'SHIPPER', 'CARRIER'].map(role => element('input', { type: 'checkbox', value: role }));
  const button = element('button', { class: 'btn btn-primary', type: 'submit', text: 'Save roles' });
  const result = element('div');
  const form = element('form', { class: 'stack', novalidate: true, 'aria-labelledby': 'roleFormTitle' },
    element('p', { id: 'roleFormTitle', class: 'field-label', text: "Change someone's roles" }),
    element('label', { class: 'stack' }, element('span', { class: 'field-label', text: 'User ID' }), user),
    element('label', { class: 'stack' }, element('span', { class: 'field-label', text: 'Organization ID' }), organization),
    element('fieldset', {}, element('legend', { class: 'field-label', text: 'Roles' }), element('div', {}, boxes.map(box => element('label', { class: 'choice' }, box, box.value))),
      element('span', { class: 'caption', text: "Saving replaces all of this person's roles in that organization. Nothing is ticked for you." })),
    element('div', {}, button), result);
  form.onsubmit = async event => {
    event.preventDefault();
    result.replaceChildren();
    const roles = boxes.filter(box => box.checked).map(box => box.value);
    const problem = !user.value.trim() ? ['Type the user ID.', user] : !organization.value.trim() ? ['Type the organization ID.', organization] : !roles.length ? ['Tick at least one role.', boxes[0]] : null;
    if (problem) { result.append(message('err', 'Not saved yet. ' + problem[0])); problem[1].focus(); return; }
    busy(button, 'Saving…');
    button.disabled = true;
    try {
      const out = await request('/v1/roles', 'POST', { userId: user.value.trim(), orgId: organization.value.trim(), roles });
      const saved = message('ok', 'Saved by you at ' + timeIST(Date.now()) + '. ' + out.userId + ' now holds only ' + inWords(out.roles) + ' in ' + out.orgId + '.');
      if (out.userId !== me.user.id) result.append(saved);
      else { await loadWorkspace(); byId('pageMessage').replaceChildren(saved); }
    } catch (error) {
      result.append(message('err', "Couldn't save the roles: " + error.message + '. ' + nothingChanged(error)));
    } finally {
      idle(button);
      button.disabled = false;
    }
  };
  return form;
}

function showNotice(text, help) {
  byId('noticeText').textContent = text;
  byId('noticeHelp').textContent = help;
  byId('notice').hidden = false;
  byId('tools').hidden = byId('sections').hidden = true;
}
async function loadSession() {
  // Ask who this is without the saved organization first: a membership removed since last time would
  // otherwise fail this call and force a fresh sign-in.
  const saved = org;
  org = '';
  me = await request('/v1/auth/me');
  org = me.organizations.some(organization => organization.id === saved) ? saved : me.organizations.length === 1 ? me.organizations[0].id : '';
  if (org) sessionStorage.setItem('navig8r_org', org); else sessionStorage.removeItem('navig8r_org');
  byId('pageMessage').replaceChildren();
  byId('signin').hidden = true;
  byId('account').hidden = false;
  byId('userName').textContent = me.user.fullName;
  byId('organization').replaceChildren(element('option', { value: '', text: 'Choose an organization' }), ...me.organizations.map(organization => element('option', { value: organization.id, text: organization.displayName + ' (' + organization.id + ')' })));
  byId('organization').value = org;
  try { await loadWorkspace(); }
  catch (error) { byId('pageMessage').replaceChildren(message('err', "Couldn't load the workspace: " + error.message + '.')); }
}
async function loadWorkspace() {
  byId('workspace').hidden = false;
  byId('roleChips').replaceChildren();
  if (!me.organizations.length) return showNotice("Your account isn't a member of any organization.", 'If you work in NaviG8r operations, ask a teammate with ADMIN to add you.');
  if (!org) return showNotice("Choose the organization you're acting for.", 'Use the Acting for list at the top right.');
  me = await request('/v1/auth/me');
  principal = me.principal;
  byId('roleChips').replaceChildren(...(principal ? principal.roles : []).map(roleChip));
  const operator = !!principal && principal.internal && principal.roles.some(role => ['OPS', 'FINANCE', 'ADMIN'].includes(role));
  if (!operator) {
    const name = (me.organizations.find(organization => organization.id === org) || {}).displayName || org;
    return showNotice("You're signed in, but you don't have an operator role for " + name + '.', "This page is for the NaviG8r operations team. If you work there, ask a teammate with ADMIN to add OPS or FINANCE, or change the organization you're acting for.");
  }
  byId('notice').hidden = true;
  byId('tools').hidden = byId('sections').hidden = false;
  renderTeam();
  await Promise.all([loadCarriers(), loadPayments()]);
}

// A second click while waiting would send a second code, and only the last one would work.
async function whileWaiting(button, action) {
  button.disabled = true;
  try { await action(); } finally { button.disabled = false; }
}
byId('start').onclick = () => whileWaiting(byId('start'), () => run(async () => {
  const out = await request('/v1/auth/otp/start', 'POST', { phone: byId('phone').value });
  challenge = out.challengeId;
  if (out.debugCode) byId('code').value = out.debugCode;
  byId('code').focus();
}, "Couldn't send the code", byId('signinResult')));
byId('verify').onclick = () => whileWaiting(byId('verify'), () => run(async () => {
  const out = await request('/v1/auth/otp/verify', 'POST', { phone: byId('phone').value, challengeId: challenge, code: byId('code').value });
  token = out.accessToken;
  org = '';
  sessionStorage.setItem('navig8r_access', token);
  sessionStorage.removeItem('navig8r_org');
  await loadSession();
}, "Couldn't sign in", byId('signinResult')));
byId('signout').onclick = () => { sessionStorage.removeItem('navig8r_access'); sessionStorage.removeItem('navig8r_org'); location.reload(); };
byId('organization').onchange = () => {
  org = byId('organization').value;
  if (org) sessionStorage.setItem('navig8r_org', org); else sessionStorage.removeItem('navig8r_org');
  run(loadWorkspace, "Couldn't switch the organization");
};
byId('carriersReload').onclick = () => run(loadCarriers, "Couldn't reload");
byId('paymentsReload').onclick = () => run(loadPayments, "Couldn't reload");
byId('legend').append(...[['Done', 'good'], ['Someone must act', 'attention'], ['Blocked or failed', 'problem'], ['In progress', 'info']].map(statusTag));
if (!token) byId('signin').hidden = false;
else {
  byId('pageMessage').replaceChildren(element('div', { class: 'msg msg-info', role: 'status' }, element('span', { class: 'spin', 'aria-hidden': 'true' }), element('span', { text: 'Loading your account…' })));
  loadSession().catch(error => {
    byId('pageMessage').replaceChildren();
    byId('signin').hidden = false;
    byId('signinResult').replaceChildren(message('err', "Couldn't open your session: " + error.message + '.'));
  });
}
`;

const page = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>NaviG8r operations (beta)</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;600;700&family=Poppins:wght@600;700&display=swap">
<style>${styles}</style></head><body>
${markup}
<script>${script}</script>
</body></html>`;
