/**
 * The "Trip cancel requests" card of /ops/beta: trips whose carrier asked NaviG8r to cancel them because they have
 * bookings. Finance cancels each booked shipment here with the existing fail-refund action, marked as coming from the
 * request so the server refuses it once the carrier withdraws; once the last one is cancelled the server cancels the
 * trip. Above them, any cancelled shipment whose money Razorpay captured after the cancel, for Finance to refund
 * in the Razorpay dashboard and then mark refunded here. Like opsConsoleBetaEwayBills.ts, both strings are pasted into that page
 * before its security fingerprints are computed, and the script uses its helpers, so it only works inside it.
 */

export const tripCancelMarkup = `
    <section id="tripCancels" class="card span3" aria-labelledby="tripCancelsTitle">
      <div class="head"><h2 id="tripCancelsTitle">Trip cancel requests</h2><span id="tripCancelsCount" class="caption"></span><div class="grow"></div><span id="tripCancelsUpdated" class="caption"></span><button id="tripCancelsReload" class="btn btn-quiet btn-sm" type="button">Reload</button></div>
      <div id="tripCancelsBody"></div>
    </section>`;

// No backticks, no dollar-brace and no backslashes in here: this sits inside a template string.
export const tripCancelScript = `
// The carrier app's words for the same four reasons.
const tripCancelReasonWords = { TRUCK_UNAVAILABLE: 'Truck not available', DRIVER_UNAVAILABLE: 'Driver not available', ROUTE_CHANGED: 'Route changed', OTHER: 'Other reason' };
const tripCancelBookingWords = { PENDING_CARRIER_ACCEPT: 'Waiting for the carrier to accept', BOOKED: 'Accepted by the carrier' };
const tripCancelPaymentWords = {
  CREATED: ['Not paid', 'info'], FAILED: ['Payment failed', 'problem'], AUTHORIZED: ['Payment held, not collected', 'info'],
  CAPTURED: ['Payment collected', 'attention'], REFUNDED: ['Refund started', 'good'], HOLD_RELEASED: ['Hold released', 'good'],
  CAPTURED_AFTER_CANCEL: ['Money collected after cancel', 'problem'],
};
Object.assign(errorWords, {
  shipment_not_refundable: 'this shipment is no longer booked, so someone may have cancelled it already',
  payment_not_refundable: "this shipment's payment is in a state the server can't cancel",
  razorpay_payment_id_missing: 'this shipment has no Razorpay payment the server can refund',
  razorpay_refund_failed: 'the refund call to Razorpay failed',
  cancel_request_withdrawn: 'the carrier withdrew this request',
  payment_not_captured_after_cancel: 'this payment is no longer waiting for a refund, so someone may have marked it already',
  refund_payment_id_mismatch: 'this is not the payment waiting for a refund. Reload the page',
});
// Not razorpay_refund_failed: the call may have reached Razorpay before it failed.
refusedBeforeChange.push('shipment_not_refundable', 'payment_not_refundable', 'razorpay_payment_id_missing', 'cancel_request_withdrawn', 'payment_not_captured_after_cancel', 'refund_payment_id_mismatch');
let tripCancelRequests = [];
let collectedAfterCancel = [];

function tripCancelDays(trip) {
  const start = Date.parse(trip.windowStart), end = Date.parse(trip.windowEnd);
  if (!Number.isFinite(start)) return '';
  const first = dateIST(start, false), last = Number.isFinite(end) ? dateIST(end, false) : first;
  return 'Leaves ' + (first === last ? first : first + ' to ' + last);
}

async function loadTripCancels() {
  byId('countTripCancels').textContent = '–';
  sectionLoading('tripCancels', 'trip cancel requests');
  try {
    const out = await request('/ops/trip-cancel-requests');
    tripCancelRequests = out.requests;
    collectedAfterCancel = out.collectedAfterCancel || [];
  }
  catch (error) { byId('tripCancelsCount').textContent = ''; sectionFailed('tripCancels', 'trip cancel requests', error, loadTripCancels); return; }
  sectionLoaded('tripCancels');
  showTripCancelCounts();
  const collected = collectedAfterCancel.length ? element('div', { class: 'body' }, collectedAfterCancel.map(collectedAfterCancelRow)) : null;
  if (!tripCancelRequests.length) {
    byId('tripCancelsBody').replaceChildren(...[collected, element('div', { class: 'body' }, element('p', { text: 'No carrier has asked to cancel a trip.' }), element('p', { class: 'caption', text: 'A trip appears here when its carrier asks NaviG8r to cancel it while shippers are booked on it.' }))].filter(Boolean));
    return;
  }
  const list = element('div');
  const more = pages(tripCancelRequests.length, 'Oldest request first.', () => {
    list.append(...tripCancelRequests.slice(list.children.length, list.children.length + pageSize).map(tripCancelCard));
    return list.children.length;
  });
  byId('tripCancelsBody').replaceChildren(...[collected, list, more].filter(Boolean));
}

function showTripCancelCounts() {
  byId('tripCancelsCount').textContent = [plural(tripCancelRequests.length, 'trip'), collectedAfterCancel.length ? plural(collectedAfterCancel.length, 'payment') + ' to refund' : ''].filter(Boolean).join(', ');
  byId('countTripCancels').textContent = tripCancelRequests.length + collectedAfterCancel.length;
}

// Razorpay captured the money after the shipment was cancelled; the server records it and leaves the shipment cancelled.
// Staff see it to triage; only Finance, who refunds it in Razorpay, gets the action. The Razorpay ids reach Finance only.
function collectedAfterCancelRow(entry) {
  const shipment = entry.shipment, payment = entry.payment || {};
  const amount = Number.isFinite(payment.amountPaise) ? ', ' + rupees(payment.amountPaise) : '';
  const ids = [payment.razorpayOrderId ? 'Razorpay order ' + payment.razorpayOrderId : '', payment.capturedAfterCancelRazorpayPaymentId ? 'payment ' + payment.capturedAfterCancelRazorpayPaymentId : ''].filter(Boolean).join(' · ');
  const finance = can('payment.refund');
  const action = element('div', { class: 'stack' });
  const row = element('div', { class: 'row top', 'aria-label': 'Money collected after cancel, ' + shipment.id },
    element('div', { class: 'stack grow' },
      element('div', { class: 'row center' }, element('strong', { text: shipment.customerOrgName + amount }), element('span', { class: 'id', text: shipment.id })),
      ids ? element('span', { class: 'caption', text: ids }) : null,
      element('p', { text: finance ? 'Money collected after cancel. Refund it in the Razorpay dashboard, then mark it refunded here.' : 'Money collected after cancel. Finance refunds this in the Razorpay dashboard.' }),
      action),
    statusTag(tripCancelPaymentWords.CAPTURED_AFTER_CANCEL));
  if (finance) {
    const open = element('button', { class: 'btn btn-secondary btn-sm', type: 'button', text: 'Mark refunded in Razorpay…' });
    const ask = element('div', { class: 'stack', hidden: true });
    const result = element('div');
    open.onclick = () => askToMarkRefunded({ entry, row, open, ask, result });
    action.append(open, ask, result);
  }
  return row;
}

// As Cancel shipment: the question takes the button's place, and Not yet has the focus.
function askToMarkRefunded(item) {
  const payment = item.entry.payment || {};
  const which = payment.capturedAfterCancelRazorpayPaymentId ? 'payment ' + payment.capturedAfterCancelRazorpayPaymentId : 'this payment';
  const amount = Number.isFinite(payment.amountPaise) ? ' of ' + rupees(payment.amountPaise) : '';
  const notYet = element('button', { class: 'btn btn-secondary btn-sm', type: 'button', text: 'Not yet' });
  const confirm = element('button', { class: 'btn btn-primary btn-sm', type: 'button', text: 'Mark refunded' });
  item.ask.replaceChildren(
    element('p', { text: 'Mark ' + which + amount + " as refunded? Do this only once you have refunded it in the Razorpay dashboard. The shipper's screen then says it is refunded. This can't be undone from the console." }),
    element('div', { class: 'row center' }, notYet, confirm));
  item.open.hidden = true;
  item.ask.hidden = false;
  item.result.replaceChildren();
  notYet.focus();
  notYet.onclick = () => { item.ask.hidden = true; item.ask.replaceChildren(); item.open.hidden = false; item.open.focus(); };
  confirm.onclick = async () => {
    notYet.disabled = confirm.disabled = true;
    busy(confirm, 'Marking…');
    try {
      const out = await request('/shipments/' + encodeURIComponent(item.entry.shipment.id) + '/mark-refunded', 'POST', { razorpayPaymentId: payment.capturedAfterCancelRazorpayPaymentId });
      const next = out.payment && out.payment.status === 'CAPTURED_AFTER_CANCEL' ? out.payment.capturedAfterCancelRazorpayPaymentId : '';
      if (!next) collectedAfterCancel = collectedAfterCancel.filter(other => other !== item.entry);
      showTripCancelCounts();
      const done = message('ok', 'Marked refunded by you at ' + timeIST(Date.now()) + '. ' + (next ? 'Razorpay also collected payment ' + next + ' on this shipment. It shows here to refund on the next reload.' : 'This leaves the list on the next reload.'));
      done.tabIndex = -1;
      item.row.replaceChildren(done);
      done.focus();
    } catch (error) {
      idle(confirm);
      notYet.disabled = confirm.disabled = false;
      item.result.replaceChildren(message('err', "Couldn't mark it refunded: " + error.message + '. ' + nothingChanged(error)));
      confirm.focus();
    }
  };
}

function tripCancelCard(item) {
  const trip = item.trip, asked = trip.cancelRequest || {};
  const route = trip.originCity + ' to ' + trip.destCity;
  const when = Number.isFinite(asked.requestedAtUtcMs) ? 'Asked ' + dateIST(asked.requestedAtUtcMs, false) + ', ' + timeIST(asked.requestedAtUtcMs) : '';
  const rows = element('tbody', {}, item.shipments.map(entry => tripCancelShipmentRow(entry, route)));
  return element('article', { 'aria-label': route + ' (' + trip.id + ')' },
    element('div', { class: 'row top' },
      element('div', { class: 'stack grow' },
        element('div', { class: 'row center' }, element('strong', { text: route }), element('span', { class: 'id', text: trip.id })),
        element('span', { class: 'caption', text: [trip.carrierDisplayName, tripCancelDays(trip), when].filter(Boolean).join(' · ') })),
      statusTag(['Carrier asked to cancel', 'attention'])),
    element('p', { text: 'Reason: ' + (tripCancelReasonWords[asked.reasonCode] || 'Reason not recognised') }),
    asked.note ? element('p', { text: 'Note from the carrier: ' + asked.note }) : null,
    element('p', { class: 'caption', text: 'The trip takes no new bookings. When the last shipment below is cancelled, the trip is cancelled too.' }),
    element('div', { class: 'scroll' }, element('table', {}, element('thead', {}, element('tr', {}, ['Shipment', 'Shipper', 'Booking', 'Payment', 'Action'].map(heading => element('th', { scope: 'col', text: heading })))), rows)));
}

function tripCancelShipmentRow(entry, route) {
  const shipment = entry.shipment, payment = entry.payment || {};
  const amount = Number.isFinite(payment.amountPaise) ? payment.amountPaise : shipment.grossPaise;
  const status = element('td', {}, statusTag(entry.settledOutsideNaviG8r ? ['Settled outside NaviG8r', 'info'] : tripCancelPaymentWords[payment.status] || ['Status not recognised', 'problem']));
  const action = element('td');
  const whyId = 'cancel-why-' + shipment.id;
  // An ERP-preauthorized booking has no Razorpay hold to release, and the server refuses to cancel it.
  if (entry.settledOutsideNaviG8r) {
    action.append(element('button', { class: 'btn btn-sm', type: 'button', disabled: true, 'aria-describedby': whyId, text: 'Cancel shipment' }),
      element('div', { id: whyId, class: 'caption', text: "This load's payment is settled outside NaviG8r through the partner's system, so it cannot be cancelled here. Ask the carrier to withdraw the request, or settle it with the partner." }));
  } else if (!can('payment.refund')) {
    action.append(element('button', { class: 'btn btn-sm', type: 'button', disabled: true, 'aria-describedby': whyId, text: 'Cancel shipment' }),
      element('div', { id: whyId, class: 'caption', text: 'Finance cancels each shipment. You hold ' + inWords(principal.roles) + '.' }));
  } else {
    const open = element('button', { class: 'btn btn-danger btn-sm', type: 'button', text: 'Cancel shipment…' });
    const ask = element('div', { class: 'stack', hidden: true });
    const result = element('div');
    open.onclick = () => askToCancelShipment({ shipment, payment, amount, route, open, ask, result, status, action });
    action.append(open, ask, result);
  }
  return element('tr', {},
    element('td', {}, element('span', { class: 'id', text: shipment.id })),
    element('td', { text: shipment.customerOrgName }),
    element('td', { text: tripCancelBookingWords[shipment.status] || 'Status not recognised' }),
    status, action);
}

function tripCancelMoneyWords(payment, amount) {
  const sum = Number.isFinite(amount) ? rupees(amount) : 'The payment';
  if (payment.status === 'AUTHORIZED') return sum + ' was never collected. Nothing is sent to Razorpay: it returns the money within 3 days of when the shipper paid.';
  if (payment.status === 'CAPTURED') return sum + ' is refunded to the shipper.';
  return 'The shipper has not paid, so no money moves.';
}

// The question takes the button's place in the row, as the carrier cards' Approve and Reject do; Keep shipment
// has the focus, so a stray Enter changes nothing.
function askToCancelShipment(row) {
  const keep = element('button', { class: 'btn btn-secondary btn-sm', type: 'button', text: 'Keep shipment' });
  const confirm = element('button', { class: 'btn btn-danger btn-sm', type: 'button', text: 'Cancel shipment' });
  row.ask.replaceChildren(
    element('p', { text: 'Cancel shipment ' + row.shipment.id + ' for ' + row.shipment.customerOrgName + '? ' + tripCancelMoneyWords(row.payment, row.amount) + " The shipper is told. This can't be undone from the console." }),
    element('div', { class: 'row center' }, keep, confirm));
  row.open.hidden = true;
  row.ask.hidden = false;
  row.result.replaceChildren();
  keep.focus();
  keep.onclick = () => { row.ask.hidden = true; row.ask.replaceChildren(); row.open.hidden = false; row.open.focus(); };
  confirm.onclick = async () => {
    keep.disabled = confirm.disabled = true;
    busy(confirm, 'Cancelling…');
    try {
      await request('/shipments/' + encodeURIComponent(row.shipment.id) + '/fail-refund', 'POST', { fromCancelRequest: true });
      const paymentAfter = { AUTHORIZED: 'HOLD_RELEASED', CAPTURED: 'REFUNDED' }[row.payment.status];
      if (paymentAfter) row.status.replaceChildren(statusTag(tripCancelPaymentWords[paymentAfter]));
      const done = message('ok', 'Cancelled by you at ' + timeIST(Date.now()) + '. The shipper is told. Once no shipment is left, the trip is cancelled and leaves this list on the next reload.');
      done.tabIndex = -1;
      row.action.replaceChildren(done);
      done.focus();
    } catch (error) {
      idle(confirm);
      keep.disabled = confirm.disabled = false;
      const after = error.code === 'razorpay_refund_failed' ? 'Check the payment in the Razorpay dashboard before trying again.' : nothingChanged(error);
      row.result.replaceChildren(message('err', "Couldn't cancel the shipment: " + error.message + '. ' + after));
      confirm.focus();
    }
  };
}

byId('tripCancelsReload').onclick = () => run(loadTripCancels, "Couldn't reload");
`;
