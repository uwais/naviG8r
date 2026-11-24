/**
 * The "Load Board" card of /ops/beta: every load a shipper posted, with its state, times and the routes carriers made
 * for it, read only and with no amounts (a posted load has none). For counting what was posted and what came of it.
 * Like opsConsoleBetaTripCancels.ts, both strings are pasted into that page before its security fingerprints are
 * computed, and the script uses its helpers, so it only works inside it.
 */

export const postedLoadMarkup = `
    <section id="postedLoads" class="card span3" aria-labelledby="postedLoadsTitle">
      <div class="head"><h2 id="postedLoadsTitle">Load Board</h2><span id="postedLoadsCount" class="caption"></span><div class="grow"></div><span id="postedLoadsUpdated" class="caption"></span><button id="postedLoadsReload" class="btn btn-quiet btn-sm" type="button">Reload</button></div>
      <div id="postedLoadsBody"></div>
    </section>`;

// No backticks, no dollar-brace and no backslashes in here: this sits inside a template string.
export const postedLoadScript = `
const postedLoadStateWords = {
  OPEN: ['On the board', 'info'], BOOKED: ['Booked', 'good'], WITHDRAWN: ['Withdrawn by the shipper', 'good'], EXPIRED: ['Expired with no booking', 'problem'],
};
let postedLoads = [];
// Pickup days are India calendar days, written YYYY-MM-DD.
const pickupDay = day => dateIST(Date.parse(day + 'T00:00:00+05:30'), false);

async function loadPostedLoads() {
  sectionLoading('postedLoads', 'posted loads');
  try { postedLoads = (await request('/ops/posted-loads')).loads; }
  catch (error) { byId('postedLoadsCount').textContent = ''; sectionFailed('postedLoads', 'posted loads', error, loadPostedLoads); return; }
  sectionLoaded('postedLoads');
  const open = postedLoads.filter(load => load.state === 'OPEN').length;
  byId('postedLoadsCount').textContent = plural(postedLoads.length, 'load') + ', ' + open + ' on the board';
  if (!postedLoads.length) {
    byId('postedLoadsBody').replaceChildren(element('div', { class: 'body' }, element('p', { text: 'No shipper has posted a load yet.' }), element('p', { class: 'caption', text: 'A load appears here when a shipper whose search found no route posts it for carriers.' })));
    return;
  }
  const list = element('div');
  const more = pages(postedLoads.length, 'Newest first.', () => {
    list.append(...postedLoads.slice(list.children.length, list.children.length + pageSize).map(postedLoadRow));
    return list.children.length;
  });
  byId('postedLoadsBody').replaceChildren(list, more);
}

function postedLoadRow(load) {
  const pickupWindow = load.earliestPickupDate === load.latestPickupDate ? pickupDay(load.earliestPickupDate) : pickupDay(load.earliestPickupDate) + ' to ' + pickupDay(load.latestPickupDate);
  const times = ['Posted ' + dateIST(load.postedAtUtcMs, false) + ' ' + timeIST(load.postedAtUtcMs), load.closedAtUtcMs ? 'closed ' + dateIST(load.closedAtUtcMs, false) + ' ' + timeIST(load.closedAtUtcMs) : ''].filter(Boolean).join(', ');
  const routes = load.routes.length ? plural(load.routes.length, 'route') + ' made: ' + inWords(load.routes.map(route => route.carrierName || route.carrierOrgId)) : 'No route made yet';
  return element('div', { class: 'row top', 'aria-label': 'Posted load ' + load.id },
    element('div', { class: 'stack grow' },
      element('div', { class: 'row center' }, element('strong', { text: load.fromCity + ' to ' + load.toCity + ', ' + load.weightKg.toLocaleString('en-IN') + ' kg' }), element('span', { class: 'id', text: load.id })),
      element('span', { class: 'caption', text: (load.shipperName || load.shipperOrgId) + ' · pickup ' + pickupWindow + ' · ' + times }),
      element('span', { class: 'caption', text: routes + (load.booking ? ' · booked as shipment ' + load.booking.shipmentId : '') })),
    statusTag(postedLoadStateWords[load.state] || ['State not recognised', 'problem']));
}

byId('postedLoadsReload').onclick = () => run(loadPostedLoads, "Couldn't reload");
`;
