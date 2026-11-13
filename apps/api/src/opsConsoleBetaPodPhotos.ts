/**
 * "View photo" on /ops/beta: the proof of delivery photos on a shipment waiting for release, one button each. The
 * photo route needs the sign-in, which a plain link cannot send, so the page fetches the photo and shows it from
 * memory in a dialog; the page's policy allows blob: images for this. Like opsConsoleBetaEwayBills.ts, both strings
 * are pasted into that page before its security fingerprints are computed, and the script uses its helpers.
 */

export const podPhotoMarkup = `
<dialog id="podPhoto" class="photo" aria-labelledby="podPhotoTitle">
  <h2 id="podPhotoTitle"></h2>
  <img id="podPhotoImage" class="pod-photo" alt="">
  <div class="pair"><button id="podPhotoClose" class="btn btn-secondary" type="button">Close</button></div>
</dialog>`;

// No backticks, no dollar-brace and no backslashes in here: this sits inside a template string.
export const podPhotoScript = `
let podPhotoAddress = '', podPhotoTrigger = null;
function podPhotoButtons(shipment) {
  const photos = Array.isArray(shipment.podPhotos) ? shipment.podPhotos : [];
  if (!photos.length) return null;
  const result = element('div');
  const buttons = photos.map((photo, index) => {
    const button = element('button', { class: 'btn btn-quiet btn-sm', type: 'button', text: photos.length === 1 ? 'View photo' : 'View photo ' + (index + 1) });
    button.onclick = () => showPodPhoto(shipment, photo, index + 1, photos.length, button, result);
    return button;
  });
  return element('div', {}, element('div', { class: 'row' }, buttons), result);
}
async function showPodPhoto(shipment, photo, number, count, trigger, result) {
  result.replaceChildren();
  busy(trigger, 'Opening…');
  trigger.disabled = true;
  const sent = token ? { authorization: 'Bearer ' + token } : {};
  if (org) sent['x-organization-id'] = org;
  let image;
  try {
    let response;
    try { response = await fetch('/v1/shipments/' + encodeURIComponent(shipment.id) + '/pod-photos/' + encodeURIComponent(photo.id), { headers: sent, signal: AbortSignal.timeout ? AbortSignal.timeout(30000) : undefined }); }
    catch { throw Error("the server didn't respond"); }
    if (response.status === 401) byId('signin').hidden = false;
    if (!response.ok) throw Error(response.status === 404 ? "this photo wasn't found" : 'the server gave an error (' + response.status + ')');
    image = await response.blob();
  } catch (error) {
    result.append(message('err', "Couldn't open the photo: " + error.message + '.'));
    return;
  } finally { idle(trigger); trigger.disabled = false; }
  if (byId('podPhoto').open) byId('podPhoto').close();
  podPhotoAddress = URL.createObjectURL(image);
  podPhotoTrigger = trigger;
  byId('podPhotoTitle').textContent = 'Proof of delivery, shipment ' + shipment.id + (count > 1 ? ', photo ' + number + ' of ' + count : '');
  byId('podPhotoImage').alt = 'Photo the carrier sent as proof of delivery';
  byId('podPhotoImage').src = podPhotoAddress;
  byId('podPhoto').showModal();
  byId('podPhotoClose').focus();
}
byId('podPhotoClose').onclick = () => byId('podPhoto').close();
// Esc closes it too; either way the photo leaves memory and focus goes back to its button.
byId('podPhoto').addEventListener('close', () => {
  byId('podPhotoImage').removeAttribute('src');
  if (podPhotoAddress) URL.revokeObjectURL(podPhotoAddress);
  podPhotoAddress = '';
  if (podPhotoTrigger && podPhotoTrigger.isConnected) podPhotoTrigger.focus();
  podPhotoTrigger = null;
});
`;
