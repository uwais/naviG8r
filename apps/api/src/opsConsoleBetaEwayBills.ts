/**
 * The e-way bill cards of /ops/beta, kept apart so the page file stays under its size cap. Both strings are
 * pasted into that page before its security fingerprints are computed, and the script shares its helpers
 * (element, request, can, message, busy and the rest), so it only works inside that page.
 * Copy follows docs/design-eway-bill/contract.md. One request, GET /ops/eway-bills, feeds both cards.
 */

// Placed after the Team access card: the first card takes the two columns beside it, the second its own row.
export const ewayBillMarkup = `
    <section id="ewayBills" class="card span2" aria-labelledby="ewayBillsTitle">
      <div class="head"><h2 id="ewayBillsTitle">E-way bills to check</h2><span id="ewayBillsCount" class="caption"></span><div class="grow"></div><span id="ewayBillsUpdated" class="caption"></span><button id="ewayBillsReload" class="btn btn-quiet btn-sm" type="button">Reload</button></div>
      <div id="ewayBillsBody"></div>
    </section>
    <section id="ewayMissing" class="card span3" aria-labelledby="ewayMissingTitle">
      <div class="head"><h2 id="ewayMissingTitle">Missing</h2><span id="ewayMissingCount" class="caption"></span><div class="grow"></div><span id="ewayMissingUpdated" class="caption"></span><button id="ewayMissingReload" class="btn btn-quiet btn-sm" type="button">Reload</button></div>
      <div id="ewayMissingBody"></div>
    </section>`;

// No backticks, no dollar-brace and no backslashes in here: this sits inside a template string.
export const ewayBillScript = `
// The government portal's address, named in docs/design-eway-bill/contract.md. Never built from server data.
const ewayPortalAddress = 'https://ewaybillgst.gov.in';
const ewayProblemWords = [['NOT_FOUND', 'Not found on the portal'], ['CANCELLED', 'Cancelled on the portal'], ['DETAILS_DO_NOT_MATCH', 'Details here do not match the portal'], ['OTHER', 'Other']];
const ewayProblemWordsByCode = Object.fromEntries(ewayProblemWords);
const ewayNotNeededWords = { BELOW_THRESHOLD: 'Below the value that needs one', GOODS_EXEMPT: 'These goods do not need one', OTHER: 'Other' };
const ewayStatusWords = { PENDING_CARRIER_ACCEPT: ['Waiting for a carrier', 'info'], BOOKED: ['Booked', 'info'] };
let ewayLists = { toCheck: [], missing: [], notNeeded: [] };
let ewayCheckedSinceLoad = new Set();

const groupedInFours = number => (String(number).match(/.{1,4}/g) || []).join(' ');
const ewayRoute = shipment => shipment.pickupAddress && shipment.dropAddress ? shipment.pickupAddress + ' to ' + shipment.dropAddress : '';
const ewayBookedAt = ms => 'Booked ' + dateIST(ms, false) + ', ' + timeIST(ms);

function showEwayCounts() {
  const waiting = ewayLists.toCheck.length - ewayCheckedSinceLoad.size;
  byId('ewayBillsCount').textContent = plural(waiting, 'bill');
  byId('countEwayBills').textContent = waiting;
  byId('ewayMissingCount').textContent = plural(ewayLists.missing.length, 'shipment');
  byId('countEwayMissing').textContent = ewayLists.missing.length;
}

async function loadEwayBills() {
  const allowed = can('eway_bill.check'), onlyOps = 'Only OPS can check e-way bills. You hold ' + inWords(principal.roles) + '.';
  const cards = [['ewayBills', 'e-way bills to check'], ['ewayMissing', 'shipments missing an e-way bill']];
  byId('ewayBillsReload').hidden = byId('ewayMissingReload').hidden = byId('jumpEwayBills').hidden = byId('jumpEwayMissing').hidden = !allowed;
  if (!allowed) {
    for (const [name] of cards) {
      byId(name + 'Count').textContent = byId(name + 'Updated').textContent = '';
      byId(name + 'Body').replaceChildren(element('div', { class: 'body' }, note(onlyOps)));
    }
    return;
  }
  byId('countEwayBills').textContent = byId('countEwayMissing').textContent = '–';
  for (const [name, what] of cards) sectionLoading(name, what);
  try { ewayLists = await request('/ops/eway-bills'); }
  catch (error) {
    for (const [name, what] of cards) { byId(name + 'Count').textContent = ''; sectionFailed(name, what, error, loadEwayBills); }
    return;
  }
  for (const [name] of cards) sectionLoaded(name);
  ewayCheckedSinceLoad = new Set();
  showEwayCounts();
  renderEwayToCheck();
  renderEwayMissing();
}

function ewayPagedList(shipments, describe, makeRow) {
  const list = element('div');
  const more = pages(shipments.length, describe, () => {
    list.append(...shipments.slice(list.children.length, list.children.length + pageSize).map(makeRow));
    return list.children.length;
  });
  return [list, more];
}

function renderEwayToCheck() {
  if (!ewayLists.toCheck.length) {
    byId('ewayBillsBody').replaceChildren(element('div', { class: 'body' }, element('p', { text: 'No e-way bills are waiting to be checked.' }), element('p', { class: 'caption', text: 'Bills appear here after a shipper adds one.' })));
    return;
  }
  byId('ewayBillsBody').replaceChildren(...ewayPagedList(ewayLists.toCheck, 'Oldest booking first.', ewayCheckRow));
}

function renderEwayMissing() {
  const body = byId('ewayMissingBody');
  if (ewayLists.missing.length) body.replaceChildren(...ewayPagedList(ewayLists.missing, 'Oldest booking first.', ewayMissingRow));
  else body.replaceChildren(element('div', { class: 'body' }, element('p', { text: 'No shipments are missing an e-way bill.' })));
  const heading = element('h3', { id: 'ewayNotNeededTitle', text: 'Shipper says no e-way bill is needed' });
  const inner = element('div', { class: 'body' }, heading);
  if (ewayLists.notNeeded.length) inner.append(...ewayPagedList(ewayLists.notNeeded, 'Oldest booking first.', ewayNotNeededRow));
  else inner.append(element('p', { text: 'No shipper has said that.' }));
  body.append(element('div', { class: 'sublist', role: 'group', 'aria-labelledby': 'ewayNotNeededTitle' }, inner));
}

function ewayShipmentHeading(shipment, extra) {
  return element('div', { class: 'row top' },
    element('div', { class: 'stack grow' }, element('div', { class: 'row center' }, element('strong', { text: shipment.customerOrgName }), element('span', { class: 'id', text: shipment.id })), element('span', { class: 'caption', text: ewayRoute(shipment) })),
    extra);
}

function ewayMissingRow(shipment) {
  return element('article', { 'aria-label': shipment.customerOrgName + ' (' + shipment.id + ')' },
    ewayShipmentHeading(shipment, statusTag(ewayStatusWords[shipment.status] || ['Status not recognised', 'problem'])),
    element('span', { class: 'caption', text: ewayBookedAt(shipment.createdAtUtcMs) }));
}

function ewayNotNeededRow(shipment) {
  const bill = shipment.ewayBill, words = ewayNotNeededWords[bill.notNeededReason] || 'Reason not recognised';
  return element('article', { 'aria-label': shipment.customerOrgName + ' (' + shipment.id + ')' },
    ewayShipmentHeading(shipment, null),
    element('span', { class: 'caption', text: ewayBookedAt(shipment.createdAtUtcMs) }),
    element('p', { text: 'Reason: ' + words + (bill.notNeededNote ? ': ' + bill.notNeededNote : '') }));
}

// What is copied is the plain value; what is shown can be grouped. Without clipboard access the value stays selectable.
function ewayDetail(label, copied, shown) {
  const status = element('span', { class: 'caption', role: 'status' });
  const copy = element('button', { class: 'btn btn-secondary btn-sm', type: 'button', text: 'Copy', 'aria-label': 'Copy ' + label });
  copy.onclick = async () => {
    try { await navigator.clipboard.writeText(copied); status.textContent = 'Copied'; }
    catch { status.textContent = 'Select it and copy it yourself.'; }
  };
  return element('div', { class: 'row center' }, element('span', { class: 'caption detail-label', text: label }), element('span', { class: 'detail-value', text: shown }), copy, status);
}

function ewayCheckRow(shipment) {
  const bill = shipment.ewayBill, name = shipment.customerOrgName, cardId = 'eway-' + shipment.id;
  const link = element('a', { href: ewayPortalAddress, target: '_blank', rel: 'noopener noreferrer', text: 'Open the government portal' });
  const found = element('button', { class: 'btn btn-primary', type: 'button', text: 'Mark as found on the portal' });
  const problem = element('button', { class: 'btn btn-secondary', type: 'button', text: 'Report a problem' });
  const actions = element('div', { class: 'row center' }, link, element('div', { class: 'grow' }), found, problem);
  const picker = element('div', { class: 'row', hidden: true });
  const result = element('div', { id: cardId + '-result' });
  const row = { shipment, result };
  found.onclick = () => saveEwayCheck(row, { result: 'FOUND' }, found, 'Saving…', [found, problem],
    'Marked as found on the portal by you at ' + timeIST(Date.now()) + '.');
  problem.onclick = () => {
    const select = element('select', { class: 'field', 'aria-labelledby': cardId + '-reason' });
    reasonChoices(select, ewayProblemWords);
    const confirm = element('button', { class: 'btn btn-danger', type: 'button', text: 'Confirm problem' });
    const back = element('button', { class: 'btn btn-secondary', type: 'button', text: 'Cancel' });
    picker.replaceChildren(
      element('label', { class: 'stack reason' }, element('span', { id: cardId + '-reason', class: 'field-label' }, 'Reason for the problem', element('span', { class: 'visually-hidden', text: ' ' + name + ' (' + shipment.id + ')' })), select),
      confirm, back);
    actions.hidden = true;
    picker.hidden = false;
    result.replaceChildren();
    select.focus();
    back.onclick = () => { picker.hidden = true; picker.replaceChildren(); actions.hidden = false; result.replaceChildren(); problem.focus(); };
    confirm.onclick = async () => {
      result.replaceChildren();
      if (!select.value) {
        select.setAttribute('aria-invalid', 'true');
        result.append(message('err', 'Not reported yet. Choose a reason from the list.'));
        select.focus();
        return;
      }
      select.removeAttribute('aria-invalid');
      const saved = await saveEwayCheck(row, { result: 'PROBLEM', problemReason: select.value }, confirm, 'Saving…', [found, problem, confirm, back, select],
        'Problem reported by you at ' + timeIST(Date.now()) + ': ' + ewayProblemWordsByCode[select.value] + '. The shipper can see this on their shipment.');
      if (saved) { picker.hidden = true; picker.replaceChildren(); actions.hidden = false; }
    };
  };
  return element('article', { 'aria-label': name + ' (' + shipment.id + ')' },
    ewayShipmentHeading(shipment, null),
    ewayDetail('E-way bill number', bill.billNumber, groupedInFours(bill.billNumber)),
    ewayDetail('Bill date', bill.billDate, bill.billDate),
    ewayDetail('GSTIN of whoever made the bill', bill.makerGstin, bill.makerGstin),
    ewayDetail('Invoice number', bill.invoiceNumber, bill.invoiceNumber),
    actions, picker, result);
}

// Controls are locked while saving so the choice cannot change under the request. The last answer wins on the
// server, so a saved row keeps its buttons for a second look.
async function saveEwayCheck(row, body, button, working, controls, savedWords) {
  const unlocked = controls.filter(control => !control.disabled);
  row.result.replaceChildren();
  unlocked.forEach(control => { control.disabled = true; });
  busy(button, working);
  try {
    await request('/ops/eway-bills/' + encodeURIComponent(row.shipment.id) + '/check', 'POST', body);
    ewayCheckedSinceLoad.add(row.shipment.id);
    showEwayCounts();
    const done = message('ok', savedWords + ' It leaves this list on the next reload.');
    done.tabIndex = -1;
    row.result.append(done);
    done.focus();
    return true;
  } catch (error) {
    row.result.append(message('err', "Couldn't save the check: " + error.message + '. ' + nothingChanged(error)));
    return false;
  } finally {
    idle(button);
    unlocked.forEach(control => { control.disabled = false; });
  }
}

byId('ewayBillsReload').onclick = () => run(loadEwayBills, "Couldn't reload");
byId('ewayMissingReload').onclick = () => run(loadEwayBills, "Couldn't reload");
`;
