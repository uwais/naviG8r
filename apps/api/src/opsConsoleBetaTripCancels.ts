/**
 * The "Trip cancel requests" card of /ops/beta: trips whose carrier asked NaviG8r to cancel them because they have
 * bookings. Finance cancels each booked shipment here with the existing fail-refund action, marked as coming from the
 * request so the server refuses it once the carrier withdraws; once the last one is cancelled the server cancels the
 * trip. Above them, any cancelled shipment whose money Razorpay captured after the cancel, for Finance to refund
 * in the Razorpay dashboard. Like opsConsoleBetaEwayBills.ts, both strings are pasted into that page
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
});
// Not razorpay_refund_failed: the call may have reached Razorpay before it failed.
refusedBeforeChange.push('shipment_not_refundable', 'payment_not_refundable', 'razorpay_payment_id_missing', 'cancel_request_withdrawn');
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
  byId('tripCancelsCount').textContent = [plural(tripCancelRequests.length, 'trip'), collectedAfterCancel.length ? plural(collectedAfterCancel.length, 'payment') + ' to refund' : ''].filter(Boolean).join(', ');
  byId('countTripCancels').textContent = tripCancelRequests.length + collectedAfterCancel.length;
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

// Razorpay captured the money after the shipment was cancelled; the server records it and leaves the shipment cancelled.
function collectedAfterCancelRow(entry) {
  const shipment = entry.shipment, payment = entry.payment || {};
  const amount = Number.isFinite(payment.amountPaise) ? ', ' + rupees(payment.amountPaise) : '';
  return element('div', { class: 'row top' },
    element('div', { class: 'stack grow' },
      element('div', { class: 'row center' }, element('strong', { text: shipment.customerOrgName + amount }), element('span', { class: 'id', text: shipment.id })),
      element('p', { text: 'Money collected after cancel. Refund it in the Razorpay dashboard.' })),
    statusTag(tripCancelPaymentWords.CAPTURED_AFTER_CANCEL));
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
  const status = element('td', {}, statusTag(tripCancelPaymentWords[payment.status] || ['Status not recognised', 'problem']));
  const action = element('td');
  const whyId = 'cancel-why-' + shipment.id;
  if (!can('payment.refund')) {
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
