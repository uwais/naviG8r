import { firebaseSignInMarkup, phoneForSignInScript, staffCountryOptions, staffSignInNotSetUpMarkup, type StaffSignIn } from "./staffSignIn.ts";

const signInControls = `<label>Country<select id="country">${staffCountryOptions}</select></label><label>Phone<input id="phone" autocomplete="tel"></label><button id="start">Send code</button><label>Verification code<input id="code" autocomplete="one-time-code"></label><button id="verify">Sign in</button>`;

const staffRoleNames = { ADMIN: "Admin: adds and removes staff", OPS: "Operations: trips, carriers and support", FINANCE: "Finance: payments and payouts" };
// Admin is not offered when adding; it is ticked in the person's row once they are listed.
const addableRoles = ["OPS", "FINANCE"] as const;
const newStaffRoleBoxes = addableRoles
  .map((role) => `<label><input type="checkbox" id="staffNew${role}" value="${role}"> ${staffRoleNames[role]}</label>`).join("");

// Shown only to someone who may manage roles; the API refuses everyone else whatever the page shows.
const staffSection = `<section id="staffManagement" hidden><h2>NaviG8r staff</h2><p>People who run NaviG8r. Someone you add signs in on this page with their phone. Shipper and carrier numbers cannot be added. To make someone an admin, add them first, then tick Admin in their row and save.</p>
<label>Reason code, used for every change below (for example NEW_STAFF)<input id="staffReason"></label><p id="staffNotice" role="status"></p><div id="staffList"></div>
<h3>Add staff</h3><label>Name<input id="staffName" autocomplete="off"></label><label>Country<select id="staffCountry">${staffCountryOptions}</select></label><label>Phone<input id="staffPhone" inputmode="tel" autocomplete="off"></label><fieldset><legend>Roles</legend>${newStaffRoleBoxes}</fieldset><button id="addStaff">Add staff</button></section>`;

const staffScript = `
const staffRoleNames = ${JSON.stringify(Object.fromEntries(Object.entries(staffRoleNames).map(([role, words]) => [role, words.split(":")[0]])))};
const staffErrors = {staff_number_has_customer_account:'This number belongs to a shipper or carrier account. Staff need a different number.',already_staff:'This person is already staff. Change their roles in their row above.',staff_name_mismatch:'This number already has an account under a different name. Check the number, or ask the person for the name on their account.',admin_needs_existing_staff:'Add the person first, then tick Admin in their row.',cannot_revoke_last_admin:'NaviG8r needs at least one admin. Make someone else an admin first.',reason_required:'Enter a reason code: 3 to 64 capitals, numbers or underscores, starting with a letter, for example NEW_STAFF.',invalid_role:'Choose at least one role.',invalid_phone:'Phone numbers have 10 digits. Check the number.',phone_country_mismatch:'The number and the country do not match. Check the country.',invalid_country_code:'Choose a country.',invalid_fullName:'Enter a name of up to 100 characters.',account_inactive:'This account was turned off and cannot be added.',staff_write_rate_limited:'Too many changes in a short time. Wait a few minutes and try again.',not_found:'This person is no longer on the staff list. Reload the page.'};
const staffAction = fn => perform(async () => { $('staffNotice').textContent=''; try { await fn(); } catch (e) { throw Error(staffErrors[e.message] || e.message); } });
const staffHeaders = () => ({'x-reason-code': $('staffReason').value.trim()});
const checkedRoles = boxes => [...boxes].filter(b => b.checked).map(b => b.value);
const addableRoles = ${JSON.stringify(addableRoles)};
const newStaffRoleBoxes = () => addableRoles.map(role => $('staffNew'+role));
const newStaffRoles = () => addableRoles.filter(role => $('staffNew'+role).checked);
async function loadStaff(){
 const out=await request('/v1/ops/staff'); $('staffList').replaceChildren();
 for(const s of out.staff){
  const row=document.createElement('article'), name=document.createElement('strong'), phone=document.createElement('small'), boxes=document.createElement('div');
  name.textContent=s.fullName; phone.textContent=s.countryCode+' number ending '+s.phoneLastFour+' · '+s.roles.map(r=>staffRoleNames[r]||r).join(', ');
  for(const role of Object.keys(staffRoleNames)){const label=document.createElement('label'),box=document.createElement('input');box.type='checkbox';box.value=role;box.checked=s.roles.includes(role);label.append(box,' '+staffRoleNames[role]);boxes.append(label);}
  const save=document.createElement('button'), remove=document.createElement('button'); save.textContent='Save roles'; remove.textContent='Remove from staff';
  const change=roles=>staffAction(async()=>{await request('/v1/ops/staff/'+encodeURIComponent(s.userId),'PUT',{roles},staffHeaders()); $('staffNotice').textContent=roles.length?'Roles saved for '+s.fullName+'.':s.fullName+' is no longer staff.'; await loadStaff();});
  save.onclick=()=>{const roles=checkedRoles(boxes.querySelectorAll('input'));if(!roles.length){$('error').textContent='Choose at least one role, or use Remove from staff.';return;}return change(roles)();};
  remove.onclick=change([]);
  row.append(name,phone,boxes,save,remove); $('staffList').append(row);
 }
}
$('addStaff').onclick=staffAction(async()=>{const out=await request('/v1/ops/staff','POST',{fullName:$('staffName').value.trim(),phone:$('staffPhone').value,countryCode:$('staffCountry').value,roles:newStaffRoles()},staffHeaders());
 $('staffName').value='';$('staffPhone').value='';newStaffRoleBoxes().forEach(b=>b.checked=false);
 $('staffNotice').textContent=out.staffMember.fullName+' is now staff. They can sign in on this page with their phone.'; await loadStaff();});
`;

// Only outside production: the server refuses these routes there.
const serverCodeSignIn = `$('phone').oninput = () => { otpPhoneRevision++; challenge = ''; $('code').value = ''; otpCooldownUntil = 0; renderOtpCooldown(); };
$('country').onchange = $('phone').oninput;
$('start').onclick = perform(async () => { const button=$('start'), previousChallenge=challenge, requestRevision=otpPhoneRevision, requestedPhone=$('phone').value, requestedCountry=$('country').value; const checked = phoneForSignIn(requestedPhone, requestedCountry); if (checked.error) throw Error(checked.words); button.disabled=true; try { const out = await request('/v1/auth/otp/start','POST',{phone:requestedPhone,countryCode:requestedCountry}); if (requestRevision !== otpPhoneRevision || requestedPhone !== $('phone').value) return; challenge = out.challengeId; if (out.debugCode !== undefined) $('code').value = out.debugCode; else if (challenge !== previousChallenge) $('code').value = ''; startOtpCooldown(out.retryAfterMs); } catch (e) { if (requestRevision !== otpPhoneRevision || requestedPhone !== $('phone').value) return; if (e.retryAfterMs) { startOtpCooldown(e.retryAfterMs); } throw e; } finally { if (requestRevision === otpPhoneRevision && (!otpCooldownUntil || otpCooldownUntil <= Date.now())) renderOtpCooldown(); } });
$('verify').onclick = perform(async () => { if(!challenge) throw Error('Start a new code before signing in.'); const out = await request('/v1/auth/otp/verify','POST',{phone:$('phone').value,countryCode:$('country').value,challengeId:challenge,code:$('code').value}); await signedIn(out.accessToken); });
`;

/** Public shell; every data request is authenticated and authorized by the API. */
export function opsPortalHtml(
  options: { workflowOnly?: boolean; operations?: boolean; signIn: StaffSignIn },
): string {
  const signIn = options.signIn;
  const loginContent = signIn.kind === "not-set-up" ? staffSignInNotSetUpMarkup
    : signIn.kind === "firebase" ? signInControls + firebaseSignInMarkup(signIn.settings, { country: "country", phone: "phone", send: "start", code: "code", verify: "verify" })
    : signInControls;
  const workflowOnly = options.workflowOnly === true;
  const heading = workflowOnly
    ? "NaviG8r shipments"
    : options.operations
      ? "Operations workspace"
      : "Full dashboard";
  const title = workflowOnly ? heading : `NaviG8r · ${heading}`;
  const fullDashboardPath = options.operations ? "/ops/v1" : "/admin/v1";
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>
<style>body{font:16px system-ui;max-width:960px;margin:32px auto;padding:16px;color:#17243b}button,input,select{padding:10px;margin:6px}article{border:1px solid #ccd3de;border-radius:8px;padding:16px;margin:12px 0}label{display:block}#error{color:#a11212}#notice{color:#16623a;font-weight:600}small{display:block;color:#526079}.ask button{min-height:48px}
${workflowOnly ? "" : "body{max-width:none;margin:0;padding:0}.dashboard-header{box-sizing:border-box;background:#102d4e;color:white;padding:20px 32px;display:flex;gap:24px;align-items:center;justify-content:space-between;font:15px system-ui,-apple-system,sans-serif}.dashboard-header strong{font-size:23px;letter-spacing:-.6px}.dashboard-header small{color:#bdd0e4;font-size:smaller}.dashboard-header nav{display:flex;gap:20px;align-items:center}.dashboard-header a{color:#d5e9ff;outline-offset:4px}.compact-dashboard{box-sizing:border-box;max-width:992px;margin:32px auto;padding:16px}.compact-dashboard input,.compact-dashboard select{box-sizing:border-box;max-width:calc(100% - 12px)}@media(max-width:650px){.dashboard-header{padding:18px;align-items:start}.dashboard-header nav{flex-direction:column;gap:8px;align-items:end}.compact-dashboard{margin:0 auto;padding:20px 14px}}"}
.compact-dashboard h1{font-size:30px;letter-spacing:-.7px;margin:0 0 6px;color:#182c45}@media(max-width:650px){.compact-dashboard h1{font-size:25px}}
</style></head><body>
${workflowOnly ? "" : `<header class="dashboard-header"><div><strong>NaviG8r</strong><small>Operations &amp; administration · V2</small></div><nav aria-label="Dashboard navigation"><a href="${fullDashboardPath}">Open full dashboard (V1)</a><a href="/workflow">Shipment / POD workspace</a></nav></header><main class="compact-dashboard">`}
<h1>${heading}</h1>${workflowOnly ? '<nav><a href="/admin">Admin workspace</a></nav><p><a href="/admin/v1">Open full dashboard (V1)</a></p>' : ""}<p id="error" role="alert"></p>
<section id="login">${loginContent}</section>
<section id="workspace" hidden><label>Acting organization<select id="organization"><option value="">Select an organization</option></select></label><button id="signout">Sign out</button><p id="roles"></p><p id="access"></p><p id="released" role="status" tabindex="-1"></p><div id="shipments"></div>
${workflowOnly ? "" : staffSection}
<section id="roleManagement" hidden><h2>Membership roles</h2><label>User ID<input id="memberUser"></label><label>Organization ID<input id="memberOrg"></label><label>Roles (comma separated)<input id="memberRoles" placeholder="OPS,FINANCE"></label><button id="saveRoles">Save roles</button></section>
<section id="compliance" hidden><h2>Carrier compliance review</h2><p id="notice" role="status"></p><label>Reason code (for example DOCUMENTS_REVIEWED)<input id="reason"></label><p>If you reject with DOCUMENTS_MISSING, BANK_DETAILS_MISMATCH, DUPLICATE_ACCOUNT or NOT_A_CARRIER, only the carrier's owner sees that reason in their app, in plain words; BANK_DETAILS_MISMATCH only if the carrier has saved bank details. Dispatchers and drivers see no reason; they are told to ask the owner for details.</p><h3>Not yet approved</h3><p id="kycEmpty" hidden>Every carrier is approved.</p><div id="kycQueue"></div><h3>Review by organization ID</h3><label>Carrier organization ID<input id="carrierOrg"></label><select id="kycStatus"><option>APPROVED</option><option>REJECTED</option></select><button id="verifyKyc">Record review</button></section></section>
${workflowOnly ? "" : "</main>"}<script>
const workflowOnly = ${workflowOnly};
let challenge = '', principal, token = sessionStorage.getItem('navig8r_access') || '', org = sessionStorage.getItem('navig8r_org') || '', otpCooldownUntil = 0, otpCooldownTimer, otpPhoneRevision = 0;
const $ = id => document.getElementById(id);
async function request(path, method = 'GET', body, extra = {}) {
 const headers = { 'content-type': 'application/json', ...extra };
 if (token) headers.authorization = 'Bearer ' + token;
 if (org) headers['x-organization-id'] = org;
 const response = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
 const out = await response.json(); if (!response.ok) { const error = Error(out.error || 'Request failed'); error.retryAfterMs = out.retryAfterMs; throw error; } return out;
}
const friendlyOtpError = message => ({otp_expired:'That code expired. Click Send code to request a new one.',otp_incorrect:'That code is incorrect. Check the latest message or click Send code to try again.',otp_too_many_wrong_codes:'Too many wrong codes. Send a new code.',otp_challenge_not_found:'That code is no longer valid. Click Send code to request a new one.',otp_challenge_used:'That code was already used. Click Send code to request a new one.'}[message] || message);
const perform = fn => async () => { $('error').textContent = ''; try { await fn(); } catch(e) { $('error').textContent = e.retryAfterMs ? 'Please wait ' + Math.ceil(e.retryAfterMs / 1000) + ' seconds before requesting another code.' : friendlyOtpError(e.message); } };
function renderOtpCooldown() {
 const button = $('start'), remaining = Math.max(0, otpCooldownUntil - Date.now());
 if (remaining) { button.disabled = true; button.textContent = 'Resend code (' + Math.ceil(remaining / 1000) + 's)'; }
 else { button.disabled = false; button.textContent = challenge ? 'Resend code' : 'Send code'; if (otpCooldownTimer) { clearInterval(otpCooldownTimer); otpCooldownTimer = undefined; } }
}
function startOtpCooldown(retryAfterMs) {
 otpCooldownUntil = Date.now() + Math.max(0, Number(retryAfterMs) || 0); renderOtpCooldown();
 if (otpCooldownUntil > Date.now()) otpCooldownTimer = setInterval(renderOtpCooldown, 250);
}
async function signedIn(accessToken) { token = accessToken; org=''; sessionStorage.setItem('navig8r_access',token); sessionStorage.removeItem('navig8r_org'); await loadOrganizations(); }
document.addEventListener('navig8r-staff-signed-in', event => perform(() => signedIn(event.detail))());
${signIn.kind === "server-code" ? phoneForSignInScript + serverCodeSignIn : ""}$('signout').onclick = () => { sessionStorage.removeItem('navig8r_access'); sessionStorage.removeItem('navig8r_org'); location.reload(); };
async function loadOrganizations() {
 const me = await request('/v1/auth/me'); $('login').hidden = true; $('workspace').hidden = false;
 $('organization').replaceChildren(new Option('Select an organization',''));
 for(const organization of me.organizations) $('organization').append(new Option(organization.displayName,organization.id));
 if(!org && me.organizations.length===1) org=me.organizations[0].id;
 $('organization').value=org; if(org) await loadWorkspace();
}
$('organization').onchange=perform(async()=>{org=$('organization').value;sessionStorage.setItem('navig8r_org',org);$('shipments').replaceChildren();principal=undefined;$('roleManagement').hidden=true;$('compliance').hidden=true;$('staffManagement')&&($('staffManagement').hidden=true);if(org) await loadWorkspace();});
async function loadWorkspace(){
 const me=await request('/v1/auth/me'); principal=me.principal; $('shipments').replaceChildren();
 if(!principal){$('access').textContent='Select an active membership.';return;}
 $('roles').textContent=principal.roles.join(', '); $('roleManagement').hidden=workflowOnly || !principal.permissions.includes('user.role_manage'); $('compliance').hidden=workflowOnly || !principal.permissions.includes('kyc.verify');
 $('access').textContent=principal.permissions.includes('payment.capture')?'Payment releases require shipper acceptance or expiry of the 48-hour hold.':'Payment release is read only for this membership.';
 const path=principal.internal?'/ops/shipments/pending-release':principal.roles.includes('SHIPPER')?'/shipments':'/v1/pilot/carrier/shipments';
 const out=await request(path);
 for(const s of out.shipments){
  const row=document.createElement('article'), title=document.createElement('strong'), status=document.createElement('p');title.textContent=s.id;status.textContent=s.status;row.append(title,status);
  const hold=document.createElement('small');hold.textContent=s.paymentReady?'Ready for payment release':s.paymentHoldUntilUtcMs?'Payment held until acceptance or '+new Date(s.paymentHoldUntilUtcMs).toLocaleString():'Awaiting POD';row.append(hold);
  if(s.status==='PENDING_RELEASE'&&principal.permissions.includes('payment.capture')){const b=document.createElement('button');b.textContent='Release payment';b.disabled=!s.paymentReady;b.onclick=perform(()=>askToRelease(row,b,s.id));row.append(b);}
  if(s.status==='PENDING_RELEASE'&&!s.podAcceptedAtUtcMs&&principal.permissions.includes('pod.accept')){const b=document.createElement('button');b.textContent='Accept POD';b.onclick=perform(async()=>{await request('/shipments/'+s.id+'/accept-pod','POST',{});await loadWorkspace();});row.append(b);}
  $('shipments').append(row);
 }
 if(!$('compliance').hidden) await loadKycQueue();
 if($('staffManagement')){$('staffManagement').hidden=!principal.permissions.includes('user.role_manage'); if(!$('staffManagement').hidden) await loadStaff();}
}
const rupees=paise=>'₹'+(paise/100).toLocaleString('en-IN',{minimumFractionDigits:paise%100?2:0,maximumFractionDigits:2});
// Releasing sends money, so the first tap only asks, with the amount, carrier and route read fresh from the server.
async function askToRelease(row,button,shipmentId){
 let detail; button.disabled=true;$('released').textContent='';
 try{detail=await request('/ops/shipments/'+encodeURIComponent(shipmentId));}finally{button.disabled=false;}
 const s=detail.shipment;
 if(s.status!=='PENDING_RELEASE'||!s.paymentReady) throw Error('This payment is no longer waiting for release. Reload to see where it stands.');
 if(!Number.isFinite(s.netToCarrierPaise)) throw Error('Release is off for this shipment: the server did not send the amount. Nothing was released.');
 const route=s.pickupAddress&&s.dropAddress?s.pickupAddress+' to '+s.dropAddress:'shipment '+s.id, credit=rupees(s.netToCarrierPaise);
 const ask=document.createElement('div'),question=document.createElement('p'),confirmRelease=document.createElement('button'),cancel=document.createElement('button');
 question.textContent='Release payment for '+route+'? '+credit+' is credited to '+detail.carrierOrgName+"'s ledger and paid out in the payout batch, not sent now.";
 confirmRelease.textContent='Confirm release';cancel.textContent='Cancel';
 ask.className='ask';ask.setAttribute('role','group');ask.setAttribute('aria-label',question.textContent);ask.append(question,confirmRelease,cancel);
 cancel.onclick=()=>{ask.remove();button.hidden=false;button.focus();};
 confirmRelease.onclick=perform(async()=>{confirmRelease.disabled=cancel.disabled=true;try{await request('/ops/shipments/'+encodeURIComponent(shipmentId)+'/release','POST',{});}finally{confirmRelease.disabled=cancel.disabled=false;}
  // The reload removes the row and its buttons, so focus moves to the result instead of being dropped.
  // The result is shown before the reload so a failed reload cannot hide a release that went through.
  $('released').textContent='Payment released for shipment '+shipmentId+': '+credit+' credited to '+detail.carrierOrgName+"'s ledger.";$('released').focus();
  try{await loadWorkspace();}catch(e){$('released').textContent+=' Released, but the list could not refresh. Reload the page.';}});
 button.hidden=true;row.append(ask);cancel.focus();
}
const kycLabels={SUBMITTED:'Bank details submitted',NOT_STARTED:'No bank details yet',REJECTED:'Rejected'};
async function loadKycQueue(){
 const out=await request('/ops/compliance/pending'); $('kycQueue').replaceChildren(); $('kycEmpty').hidden=out.organizations.length>0;
 for(const o of out.organizations){
  const row=document.createElement('article'), name=document.createElement('strong'), detail=document.createElement('small');
  name.textContent=o.displayName; detail.textContent=(kycLabels[o.kycStatus]||o.kycStatus)+' · joined '+new Date(o.createdAtUtcMs).toLocaleDateString()+' · '+o.id; row.append(name,detail);
  for(const status of ['APPROVED','REJECTED']){const b=document.createElement('button');b.textContent=status==='APPROVED'?'Approve':'Reject';b.onclick=perform(()=>recordReview(o.id,status));row.append(b);}
  $('kycQueue').append(row);
 }
}
async function recordReview(orgId,status){
 const reason=$('reason').value.trim(), buttons=$('compliance').querySelectorAll('button');
 if(!orgId) throw Error('Enter the carrier organization ID.');
 if(!/^[A-Z][A-Z0-9_]{2,63}$/.test(reason)) throw Error('Reason code must be 3 to 64 capitals, numbers or underscores, starting with a letter, for example DOCUMENTS_REVIEWED.');
 buttons.forEach(b=>b.disabled=true);
 try{
  const out=await request('/v1/organizations/'+encodeURIComponent(orgId)+'/kyc','POST',{status},{'x-reason-code':reason});
  $('reason').value=''; $('notice').textContent='Last review recorded: '+out.org.displayName+' ('+out.org.id+') is now '+out.org.kycStatus+'.';
  await loadKycQueue();
 }finally{buttons.forEach(b=>b.disabled=false);}
}
$('saveRoles').onclick=perform(async()=>{await request('/v1/roles','POST',{userId:$('memberUser').value,orgId:$('memberOrg').value,roles:$('memberRoles').value.split(',').map(s=>s.trim()).filter(Boolean)});await loadWorkspace();});
${workflowOnly ? "" : staffScript}$('verifyKyc').onclick=perform(()=>recordReview($('carrierOrg').value.trim(),$('kycStatus').value));
if(token) perform(loadOrganizations)();
</script></body></html>`;
}
