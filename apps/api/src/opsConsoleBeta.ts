import { createHash } from "node:crypto";
import { opsConsoleBetaStyles } from "./opsConsoleBetaStyles.ts";

/**
 * The redesigned operations page, served at /ops/beta beside the current /ops page until the team agrees
 * to switch. Like /ops it is a public shell: the API authorizes every request the page makes.
 * Built from the "NaviG8r ops console" design on the NaviG8r design system; token names match that system.
 *
 * Over 500 lines because markup and script are one screen: every element id the script reads is defined
 * here, and splitting them would leave each half unreadable without the other. The stylesheet lives apart.
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
      <form id="byIdForm" class="body" novalidate autocomplete="off">
        <p class="caption">For carriers not in the list, such as taking back an approval. The change and your reason are kept in the carrier's history.</p>
        <div id="byIdOff"></div>
        <label class="stack"><span class="field-label">Carrier ID</span><input id="byIdCarrier" class="field mono" autocomplete="off" spellcheck="false"></label>
        <fieldset><legend class="field-label">Decision</legend>
          <div><label class="choice"><input type="radio" name="decision" value="APPROVED">Approve</label><label class="choice"><input type="radio" name="decision" value="REJECTED">Reject</label></div>
          <span class="caption">Nothing is chosen for you. Pick one.</span></fieldset>
        <label class="stack"><span id="byIdReasonLabel" class="field-label">Reason</span><select id="byIdReason" class="field" aria-labelledby="byIdReasonLabel" disabled></select></label>
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
<footer class="caption"><span>NaviG8r operations</span><span>All times IST, 24-hour</span><span>This is the beta page. Today's pages are still at <a href="/ops">/ops</a> and <a href="/ops/v1">/ops/v1</a>.</span></footer>
`;

// Browser code. Every name or ID from the server goes in through textContent, never as HTML.
const script = `
const byId = id => document.getElementById(id);
let token = sessionStorage.getItem('navig8r_access') || '';
let org = sessionStorage.getItem('navig8r_org') || '';
let challenge = '', me = null, principal = null, releasing = null, releaseBusy = false;
// Agreed with the team on 30 Sep. Each code must keep the reason format the audit record expects
// (see recordAudit in rbac.ts). The words shown must claim no more than the code records.
const reasons = {
  APPROVED: [['DOCUMENTS_REVIEWED', 'Documents reviewed'], ['BANK_DETAILS_VERIFIED', 'Bank details verified']],
  REJECTED: [['DOCUMENTS_MISSING', 'Documents missing'], ['BANK_DETAILS_MISMATCH', "Bank account name doesn't match the carrier"],
    ['DUPLICATE_ACCOUNT', 'Duplicate account'], ['NOT_A_CARRIER', 'Not a carrier business']],
};
// Only Review any carrier by ID reaches approved carriers, so only it offers taking an approval back.
const approvalTakenBack = ['APPROVAL_REVOKED', 'Approval taken back'];
const reasonWords = Object.fromEntries([...reasons.APPROVED, ...reasons.REJECTED, approvalTakenBack]);
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
  otp_rate_limited: 'too many codes were asked for, so wait until Send code is ready again',
  user_not_found: 'no account uses that phone number',
  invalid_phone: "that phone number isn't valid",
  shipment_not_pending_release: 'this shipment is no longer waiting for release, so someone may have released it already',
  checkout_not_completed_for_pod: "the shipper hasn't finished paying for this shipment",
  payment_not_captured: "the shipper's payment hasn't been collected",
  shipment_not_found: "that shipment wasn't found",
  payment_not_found: 'this shipment has no payment record the server can use',
  payment_id_missing: 'this shipment has no payment record the server can use',
  invalid_organization: "the organization you're acting for isn't valid",
  account_inactive: 'this account is switched off',
  membership_inactive: "your membership of that organization is switched off",
  active_organization_required: "choose the organization you're acting for first",
  cannot_revoke_last_admin: 'that would leave the organization with no one holding ADMIN',
  internal_error: 'the server hit an error',
  // The server also sends this for any failure it did not name, a payment provider error included.
  bad_request: 'the server hit an error it did not name',
};
// The server refuses with these before it changes anything. Any other error may come after a change was
// made and not saved, so the page must not say nothing happened.
const refusedBeforeChange = ['unauthorized', 'forbidden', 'not_found', 'self_verification_forbidden', 'verification_status_and_reason_required',
  'invalid_role', 'payment_hold_active', 'shipment_not_found', 'payment_not_found', 'payment_id_missing', 'checkout_not_completed_for_pod', 'shipment_not_pending_release',
  'membership_inactive', 'active_organization_required', 'cannot_revoke_last_admin'];
async function request(path, method = 'GET', body, headers = {}) {
  const sent = { 'content-type': 'application/json', ...headers };
  if (token) sent.authorization = 'Bearer ' + token;
  if (org) sent['x-organization-id'] = org;
  let response;
  // A request that hangs would otherwise leave a busy button, or the release dialog, stuck until a reload.
  const signal = AbortSignal.timeout ? AbortSignal.timeout(30000) : undefined;
  try { response = await fetch(path, { method, headers: sent, body: body === undefined ? undefined : JSON.stringify(body), signal }); }
  catch { throw Object.assign(Error("the server didn't respond"), { answered: false, unchanged: false }); }
  let out;
  try { out = await response.json(); }
  catch {
    // A success whose answer was cut off (the time limit can land mid-answer) must not pass for a success.
    if (response.ok) throw Object.assign(Error("the server's answer was cut off"), { answered: false, unchanged: false });
    out = {};
  }
  const code = out.error || String(response.status);
  if (response.status === 401) byId('signin').hidden = false;
  if (!response.ok) throw Object.assign(Error(errorWords[code] || "the server gave an error this page doesn't recognise (" + code + ')'), { answered: true, unchanged: refusedBeforeChange.includes(code), retryAfterMs: out.retryAfterMs });
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

let carriers = [], approvedSinceLoad = 0;
function showWaitingCount() {
  const waiting = carriers.length - approvedSinceLoad;
  byId('carriersCount').textContent = plural(waiting, 'carrier');
  byId('countCarriers').textContent = waiting;
}
function reasonChoices(select, list) {
  select.replaceChildren(element('option', { value: '', text: 'Choose a reason' }), ...list.map(([code, words]) => element('option', { value: code, text: words })));
}
function resetByIdReason() {
  byId('byIdReason').replaceChildren(element('option', { value: '', text: 'Choose Approve or Reject first' }));
  byId('byIdReason').disabled = true;
}
async function loadCarriers() {
  const allowed = can('kyc.verify'), onlyOps = 'Only OPS can review carriers. You hold ' + inWords(principal.roles) + '.';
  byId('carriersReload').hidden = byId('jumpCarriers').hidden = !allowed;
  byId('byIdOff').replaceChildren(allowed ? '' : note(onlyOps));
  for (const control of byId('byIdForm').elements) control.disabled = !allowed;
  if (!document.querySelector('input[name=decision]:checked')) resetByIdReason();
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
  approvedSinceLoad = 0;
  showWaitingCount();
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

// Choosing Approve or Reject first, then a reason from that action's list, is the order the team asked for.
function carrierCard(carrier) {
  const name = carrier.displayName, cardId = 'carrier-' + carrier.id, ownId = cardId + '-own';
  const own = me.organizations.some(organization => organization.id === carrier.id);
  const status = element('span', {}, statusTag(carrierStatus(carrier.kycStatus)));
  const approve = element('button', { class: 'btn btn-primary', type: 'button', text: 'Approve' });
  const reject = element('button', { class: 'btn btn-danger', type: 'button', text: 'Reject' });
  const actions = element('div', { class: 'row center' }, approve, element('div', { class: 'grow' }), reject);
  const picker = element('div', { class: 'row', hidden: true });
  const result = element('div', { id: cardId + '-result' });
  const meta = [kindWords[carrier.kind], 'joined ' + dateIST(carrier.createdAtUtcMs)].filter(Boolean).join(' · ');
  if (own) for (const button of [approve, reject]) { button.disabled = true; button.setAttribute('aria-describedby', ownId); }
  const choose = decision => {
    const approving = decision === 'APPROVED';
    const select = element('select', { class: 'field', 'aria-labelledby': cardId + '-reason' });
    reasonChoices(select, reasons[decision]);
    const confirm = element('button', { class: 'btn ' + (approving ? 'btn-primary' : 'btn-danger'), type: 'button', text: approving ? 'Confirm approval' : 'Confirm rejection' });
    const back = element('button', { class: 'btn btn-secondary', type: 'button', text: 'Cancel' });
    picker.replaceChildren(
      element('label', { class: 'stack reason' }, element('span', { id: cardId + '-reason', class: 'field-label' }, approving ? 'Reason for approving' : 'Reason for rejecting', element('span', { class: 'visually-hidden', text: ' ' + name + ' (' + carrier.id + ')' })), select),
      confirm, back);
    actions.hidden = true;
    picker.hidden = false;
    result.replaceChildren();
    select.focus();
    back.onclick = () => { picker.hidden = true; picker.replaceChildren(); actions.hidden = false; result.replaceChildren(); (approving ? approve : reject).focus(); };
    confirm.onclick = () => recordReview({ carrier, decision, select, confirm, result, status, locks: [confirm, back] });
  };
  approve.onclick = () => choose('APPROVED');
  reject.onclick = () => choose('REJECTED');
  return element('article', { 'aria-label': name + ' (' + carrier.id + ')' },
    element('div', { class: 'row top' },
      element('div', { class: 'stack grow' }, element('div', { class: 'row center' }, element('strong', { text: name }), element('span', { class: 'id', text: carrier.id })), element('span', { class: 'caption', text: meta })),
      status),
    actions, picker,
    own ? element('span', { id: ownId, class: 'caption', text: "You can't review your own organization. Ask another teammate with OPS." }) : null,
    result);
}

async function recordReview({ carrier, decision, select, confirm, result, status, locks }) {
  const approving = decision === 'APPROVED', code = select.value;
  result.replaceChildren();
  if (!code) {
    select.setAttribute('aria-invalid', 'true');
    result.append(message('err', (approving ? 'Not approved yet. ' : 'Not rejected yet. ') + 'Choose a reason from the list.'));
    select.focus();
    return;
  }
  select.removeAttribute('aria-invalid');
  const unlocked = [...document.querySelectorAll('#carriers button, #byIdForm button')].filter(button => !button.disabled);
  unlocked.forEach(button => { button.disabled = true; });
  select.disabled = true;
  busy(confirm, approving ? 'Approving…' : 'Rejecting…');
  try {
    const out = await request('/v1/organizations/' + encodeURIComponent(carrier.id) + '/kyc', 'POST', { status: decision }, { 'x-reason-code': code });
    idle(confirm);
    unlocked.filter(button => !locks.includes(button)).forEach(button => { button.disabled = false; });
    locks.forEach(button => button.setAttribute('aria-describedby', result.id));
    status.replaceChildren(statusTag(carrierStatus(out.org.kycStatus)));
    if (out.org.kycStatus === 'APPROVED') { approvedSinceLoad += 1; showWaitingCount(); }
    const by = ' by you at ' + timeIST(Date.now()) + ': ' + reasonWords[code] + '. ';
    const change = ' To change this decision, use Review any carrier by ID.';
    const done = message('ok', approving
      ? 'Approved' + by + out.org.displayName + ' can now accept shipments. It leaves this list on the next reload.' + change
      : 'Not approved' + by + out.org.displayName + " can't accept shipments until it is approved." + change);
    done.tabIndex = -1;
    result.append(done);
    done.focus();
  } catch (error) {
    idle(confirm);
    select.disabled = false;
    unlocked.forEach(button => { button.disabled = false; });
    result.append(message('err', "Couldn't save the review: " + error.message + '. ' + nothingChanged(error) + ' Your choice is kept.'));
    confirm.focus();
  }
}

for (const decision of document.querySelectorAll('input[name=decision]')) {
  decision.onchange = () => {
    reasonChoices(byId('byIdReason'), decision.value === 'APPROVED' ? reasons.APPROVED : [...reasons.REJECTED, approvalTakenBack]);
    byId('byIdReason').disabled = false;
  };
}
byId('byIdForm').onsubmit = async event => {
  event.preventDefault();
  const result = byId('byIdResult'), button = byId('byIdForm').querySelector('button'), idInput = byId('byIdCarrier'), reasonSelect = byId('byIdReason');
  const carrierId = idInput.value.trim(), code = reasonSelect.value, picked = document.querySelector('input[name=decision]:checked');
  result.replaceChildren();
  reasonSelect.removeAttribute('aria-invalid');
  const problem = !carrierId ? ['Type the carrier ID.', idInput] : !picked ? ['Pick Approve or Reject.', document.querySelector('input[name=decision]')]
    : !code ? ['Choose a reason from the list.', reasonSelect] : null;
  if (problem) {
    if (problem[1] === reasonSelect) reasonSelect.setAttribute('aria-invalid', 'true');
    result.append(message('err', 'Not recorded yet. ' + problem[0]));
    problem[1].focus();
    return;
  }
  // Every control is locked while saving, so the decision and reason cannot change under the request.
  const unlocked = [...document.querySelectorAll('#carriers button'), ...byId('byIdForm').elements].filter(control => !control.disabled);
  unlocked.forEach(control => { control.disabled = true; });
  busy(button, 'Recording…');
  let saved = false;
  try {
    const out = await request('/v1/organizations/' + encodeURIComponent(carrierId) + '/kyc', 'POST', { status: picked.value }, { 'x-reason-code': code });
    const done = message('ok', 'Review recorded by you at ' + timeIST(Date.now()) + ': ' + reasonWords[code] + '. ' + out.org.displayName + ' (' + out.org.id + ') now shows: ' + carrierStatus(out.org.kycStatus)[0] + '.');
    done.tabIndex = -1;
    result.append(done);
    saved = true;
  } catch (error) {
    result.append(message('err', "Couldn't record the review: " + error.message + '. ' + nothingChanged(error)));
  } finally {
    idle(button);
    unlocked.forEach(control => { if (control.isConnected) control.disabled = false; });
  }
  if (!saved) { button.focus(); return; }
  idInput.value = '';
  for (const decision of document.querySelectorAll('input[name=decision]')) decision.checked = false;
  resetByIdReason();
  result.lastChild.focus();
  await loadCarriers();
};

let payments = [], releasedSinceLoad = 0;
function showPaymentCount() {
  const waiting = payments.length - releasedSinceLoad;
  byId('paymentsCount').textContent = plural(waiting, 'shipment');
  byId('countPayments').textContent = waiting;
}
async function loadPayments() {
  byId('countPayments').textContent = '–';
  sectionLoading('payments', 'payments waiting for release');
  try { payments = (await request('/ops/shipments/pending-release')).shipments; }
  catch (error) { byId('paymentsCount').textContent = ''; sectionFailed('payments', 'payments waiting for release', error, loadPayments); return; }
  sectionLoaded('payments');
  payments.sort((first, second) => (first.podAtUtcMs ?? Infinity) - (second.podAtUtcMs ?? Infinity));
  releasedSinceLoad = 0;
  showPaymentCount();
  if (!payments.length) {
    byId('paymentsBody').replaceChildren(element('div', { class: 'body' }, element('p', { text: 'No payments are waiting for release.' }), element('p', { class: 'caption', text: 'Shipments appear here after the driver uploads proof of delivery.' })));
    return;
  }
  const showAmounts = payments.some(shipment => Number.isFinite(shipment.netToCarrierPaise));
  const headings = ['Shipment', 'Carrier', 'Status', 'Proof of delivery', ...(showAmounts ? ['Ledger credit'] : []), 'Action'];
  const rows = element('tbody');
  const more = pages(payments.length, 'Oldest proof of delivery first.', () => {
    rows.append(...payments.slice(rows.children.length, rows.children.length + pageSize).map(shipment => paymentRow(shipment, showAmounts)));
    return rows.children.length;
  });
  byId('paymentsBody').replaceChildren(...[
    element('div', { class: 'scroll' }, element('table', {}, element('thead', {}, element('tr', {}, headings.map(heading => element('th', { scope: 'col', class: heading === 'Ledger credit' ? 'num' : null, text: heading })))), rows)),
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
// One release opens at a time, and none while another is still saving, so a slow reply can never land in
// another shipment's dialog.
let openingRelease = false;
async function openRelease(row) {
  if (releaseBusy) return row.result.replaceChildren(note('Another release is still saving. Try again when it finishes.'));
  if (openingRelease || byId('release').open) return;
  openingRelease = true;
  row.result.replaceChildren();
  busy(row.trigger, 'Opening…');
  row.trigger.disabled = true;
  let detail;
  try { detail = await request('/ops/shipments/' + encodeURIComponent(row.shipment.id)); }
  catch (error) { row.result.append(message('err', "Couldn't open the release: " + error.message + '. Nothing was released.')); return; }
  finally { idle(row.trigger); row.trigger.disabled = false; openingRelease = false; }
  if (!row.trigger.isConnected) return;
  const fresh = detail.shipment, amounts = [fresh.grossPaise, fresh.commissionPaise, fresh.netToCarrierPaise];
  if (fresh.status !== 'PENDING_RELEASE' || !fresh.paymentReady) {
    row.result.append(message('err', 'This shipment is no longer ready for release; it may have been released already, by a teammate or by an earlier attempt. Reload the list to see where it stands. Opening this did not release anything.'));
    return;
  }
  if (!amounts.every(Number.isFinite)) {
    row.result.append(message('err', "Release is off for this shipment: the server didn't send all three amounts (shipper paid, commission, ledger credit)."));
    return;
  }
  const [gross, commission, net] = amounts, otherFees = gross - commission - net;
  byId('releaseTitle').textContent = 'Release payment for shipment ' + fresh.id + '?';
  byId('releaseText').replaceChildren(rupees(net) + ' is credited to the ledger balance of ' + detail.carrierOrgName + ' ', element('span', { class: 'id', text: fresh.carrierId }),
    ". It is paid out with the first Wednesday 18:00 IST payout batch on or after the 7th day after proof of delivery, or within minutes if that batch has already passed, to the bank account on file; if there is none yet, the payout waits until one is added. This can't be undone from the console.");
  byId('releaseMoney').replaceChildren(...[
    moneyLine('Shipper paid', rupees(gross)),
    moneyLine('NaviG8r commission', '− ' + rupees(commission)),
    otherFees ? moneyLine('Other fees and adjustments', (otherFees > 0 ? '− ' : '+ ') + rupees(Math.abs(otherFees))) : null,
    moneyLine('Credited to the ledger balance', rupees(net), true)].filter(Boolean));
  byId('releaseConfirm').textContent = 'Release ' + rupees(net);
  byId('releaseResult').replaceChildren();
  releasing = { ...row, credit: rupees(net) };
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
// A browser may still close the dialog on a second Esc while the release is saving. The outcome then goes to
// the shipment's row, or to the top of the page if a reload has replaced that row, and focus is left alone.
byId('releaseConfirm').onclick = async () => {
  const row = releasing, confirm = byId('releaseConfirm'), cancel = byId('releaseCancel');
  if (!row) return;
  busy(confirm, 'Releasing…');
  confirm.disabled = cancel.disabled = releaseBusy = true;
  byId('releaseResult').replaceChildren(message('info', 'Releasing. Cancel is off until the server answers, which takes at most 30 seconds.'));
  let outcome;
  try {
    await request('/ops/shipments/' + encodeURIComponent(row.shipment.id) + '/release', 'POST', {});
    outcome = message('ok', 'Payment released by you at ' + timeIST(Date.now()) + '. ' + row.credit + " is credited to the carrier's ledger balance for payout.");
  } catch (error) {
    outcome = message('err', "Couldn't release the payment: " + error.message + '. ' + (error.unchanged ? 'Nothing was released by this attempt.' : 'It may or may not have gone through. Reload the list and check before trying again.'));
  } finally {
    releaseBusy = false;
    idle(confirm);
    confirm.disabled = cancel.disabled = false;
  }
  const released = outcome.classList.contains('msg-ok'), dialogWasOpen = byId('release').open, rowOnPage = row.action.isConnected;
  if (dialogWasOpen && !released) return byId('releaseResult').replaceChildren(outcome);
  releasing = null;
  if (dialogWasOpen) byId('release').close();
  if (!rowOnPage) {
    // The list was reloaded meanwhile and already shows the shipment as it now stands, so the counts stay.
    outcome.firstChild.textContent = 'Shipment ' + row.shipment.id + ': ' + outcome.firstChild.textContent;
    return byId('pageMessage').replaceChildren(outcome);
  }
  if (released) {
    row.status.replaceChildren(statusTag(['Payment released', 'good']));
    row.action.replaceChildren(outcome);
    releasedSinceLoad += 1;
    showPaymentCount();
  } else row.result.replaceChildren(outcome);
  if (dialogWasOpen) { outcome.tabIndex = -1; outcome.focus(); }
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
    let out;
    try {
      out = await request('/v1/roles', 'POST', { userId: user.value.trim(), orgId: organization.value.trim(), roles });
    } catch (error) {
      result.append(message('err', "Couldn't save the roles: " + error.message + '. ' + nothingChanged(error)));
      return;
    } finally {
      idle(button);
      button.disabled = false;
    }
    const saved = 'Saved by you at ' + timeIST(Date.now()) + '. ' + out.userId + ' now holds only ' + inWords(out.roles) + ' in ' + out.orgId + '.';
    if (out.userId !== me.user.id) return result.append(message('ok', saved));
    // Your own roles changed, so the page has to reload what you can see.
    try { await loadWorkspace(); byId('pageMessage').replaceChildren(message('ok', saved)); }
    catch (error) { byId('pageMessage').replaceChildren(message('err', saved + " Couldn't refresh the page: " + error.message + '. Reload it to see your new roles.')); }
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

// A second click while a sign-in is still running would try the same code again and fail confusingly.
async function whileWaiting(button, words, action) {
  button.disabled = true;
  busy(button, words);
  try { await action(); } finally { idle(button); button.disabled = false; }
}
// The server hands back the same code until its resend wait is over, so Send code stays off until then.
let resendTimer = null;
function waitToResend(ms) {
  const button = byId('start'), until = Date.now() + ms;
  clearInterval(resendTimer);
  const tick = () => {
    const seconds = Math.ceil((until - Date.now()) / 1000);
    if (seconds <= 0) { clearInterval(resendTimer); button.disabled = false; button.textContent = 'Send code'; return false; }
    button.disabled = true;
    button.textContent = 'Send again in ' + (seconds > 90 ? Math.ceil(seconds / 60) + ' min' : seconds + 's');
    return true;
  };
  if (tick()) resendTimer = setInterval(tick, 1000);
}
// A new phone number starts over: the old code, wait and any reply still on its way belong to the old number.
byId('phone').oninput = () => {
  challenge = '';
  byId('code').value = '';
  byId('signinResult').replaceChildren();
  waitToResend(0);
};
byId('start').onclick = async () => {
  const phone = byId('phone').value;
  byId('start').disabled = true;
  byId('start').textContent = 'Sending…';
  byId('signinResult').replaceChildren();
  try {
    const out = await request('/v1/auth/otp/start', 'POST', { phone });
    if (byId('phone').value !== phone) return;
    challenge = out.challengeId;
    if (out.debugCode) byId('code').value = out.debugCode;
    byId('code').focus();
    waitToResend(out.retryAfterMs || 0);
  } catch (error) {
    if (byId('phone').value !== phone) return;
    byId('signinResult').replaceChildren(message('err', "Couldn't send the code: " + error.message + '.'));
    waitToResend(error.retryAfterMs || 0);
  }
};
byId('verify').onclick = () => whileWaiting(byId('verify'), 'Signing in…', () => run(async () => {
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
<style>${opsConsoleBetaStyles}</style></head><body>
${markup}
<script>${script}</script>
</body></html>`;

const sha256 = (text: string): string => "'sha256-" + createHash("sha256").update(text).digest("base64") + "'";
/** Only this page's own script and stylesheet may run, fonts come only from Google, and data stays on this server. */
export const opsConsoleBetaContentSecurityPolicy = [
  "default-src 'self'",
  "script-src " + sha256(script),
  "style-src " + sha256(opsConsoleBetaStyles) + " https://fonts.googleapis.com",
  "font-src https://fonts.gstatic.com",
  "frame-src 'none'",
  "object-src 'none'",
  "base-uri 'none'",
  "form-action 'self'",
  "frame-ancestors 'none'",
].join("; ");
