/** Public shell; every data request is authenticated and authorized by the API. */
export function opsPortalHtml(
  options: { workflowOnly?: boolean; operations?: boolean } = {},
): string {
  const workflowOnly = options.workflowOnly === true;
  const heading = workflowOnly
    ? "NaviG8r shipments"
    : options.operations
      ? "Operations workspace"
      : "Full dashboard";
  const title = workflowOnly ? heading : `NaviG8r · ${heading}`;
  const fullDashboardPath = options.operations ? "/ops/v1" : "/admin/v1";
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>
<style>body{font:16px system-ui;max-width:960px;margin:32px auto;padding:16px;color:#17243b}button,input,select{padding:10px;margin:6px}article{border:1px solid #ccd3de;border-radius:8px;padding:16px;margin:12px 0}label{display:block}#error{color:#a11212}#notice{color:#16623a;font-weight:600}small{display:block;color:#526079}
${workflowOnly ? "" : "body{max-width:none;margin:0;padding:0}.dashboard-header{box-sizing:border-box;background:#102d4e;color:white;padding:20px 32px;display:flex;gap:24px;align-items:center;justify-content:space-between;font:15px system-ui,-apple-system,sans-serif}.dashboard-header strong{font-size:23px;letter-spacing:-.6px}.dashboard-header small{color:#bdd0e4;font-size:smaller}.dashboard-header nav{display:flex;gap:20px;align-items:center}.dashboard-header a{color:#d5e9ff;outline-offset:4px}.compact-dashboard{box-sizing:border-box;max-width:992px;margin:32px auto;padding:16px}.compact-dashboard input,.compact-dashboard select{box-sizing:border-box;max-width:calc(100% - 12px)}@media(max-width:650px){.dashboard-header{padding:18px;align-items:start}.dashboard-header nav{flex-direction:column;gap:8px;align-items:end}.compact-dashboard{margin:0 auto;padding:20px 14px}}"}
.compact-dashboard h1{font-size:30px;letter-spacing:-.7px;margin:0 0 6px;color:#182c45}@media(max-width:650px){.compact-dashboard h1{font-size:25px}}
</style></head><body>
${workflowOnly ? "" : `<header class="dashboard-header"><div><strong>NaviG8r</strong><small>Operations &amp; administration · V2</small></div><nav aria-label="Dashboard navigation"><a href="${fullDashboardPath}">Open full dashboard (V1)</a><a href="/workflow">Shipment / POD workspace</a></nav></header><main class="compact-dashboard">`}
<h1>${heading}</h1>${workflowOnly ? '<nav><a href="/admin">Admin workspace</a></nav><p><a href="/admin/v1">Open full dashboard (V1)</a></p>' : ""}<p id="error" role="alert"></p>
<section id="login"><label>Phone<input id="phone" autocomplete="tel"></label><button id="start">Send code</button><label>Verification code<input id="code" autocomplete="one-time-code"></label><button id="verify">Sign in</button></section>
<section id="workspace" hidden><label>Acting organization<select id="organization"><option value="">Select an organization</option></select></label><button id="signout">Sign out</button><p id="roles"></p><p id="access"></p><div id="shipments"></div>
<section id="roleManagement" hidden><h2>Membership roles</h2><label>User ID<input id="memberUser"></label><label>Organization ID<input id="memberOrg"></label><label>Roles (comma separated)<input id="memberRoles" placeholder="OPS,FINANCE"></label><button id="saveRoles">Save roles</button></section>
<section id="compliance" hidden><h2>Carrier compliance review</h2><p id="notice" role="status"></p><label>Reason code (for example DOCUMENTS_REVIEWED)<input id="reason"></label><h3>Not yet approved</h3><p id="kycEmpty" hidden>Every carrier is approved.</p><div id="kycQueue"></div><h3>Review by organization ID</h3><label>Carrier organization ID<input id="carrierOrg"></label><select id="kycStatus"><option>APPROVED</option><option>REJECTED</option></select><button id="verifyKyc">Record review</button></section></section>
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
const friendlyOtpError = message => ({otp_expired:'That code expired. Click Send code to request a new one.',otp_incorrect:'That code is incorrect. Check the latest message or click Send code to try again.',otp_attempts_exceeded:'That code was entered wrong too many times. Click Send code to request a new one.',otp_challenge_not_found:'That code is no longer valid. Click Send code to request a new one.',otp_challenge_used:'That code was already used. Click Send code to request a new one.'}[message] || message);
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
$('phone').oninput = () => { otpPhoneRevision++; challenge = ''; $('code').value = ''; otpCooldownUntil = 0; renderOtpCooldown(); };
$('start').onclick = perform(async () => { const button=$('start'), previousChallenge=challenge, requestRevision=otpPhoneRevision, requestedPhone=$('phone').value; button.disabled=true; try { const out = await request('/v1/auth/otp/start','POST',{phone:requestedPhone}); if (requestRevision !== otpPhoneRevision || requestedPhone !== $('phone').value) return; challenge = out.challengeId; if (out.debugCode !== undefined) $('code').value = out.debugCode; else if (challenge !== previousChallenge) $('code').value = ''; startOtpCooldown(out.retryAfterMs); } catch (e) { if (requestRevision !== otpPhoneRevision || requestedPhone !== $('phone').value) return; if (e.retryAfterMs) { startOtpCooldown(e.retryAfterMs); } throw e; } finally { if (requestRevision === otpPhoneRevision && (!otpCooldownUntil || otpCooldownUntil <= Date.now())) renderOtpCooldown(); } });
$('verify').onclick = perform(async () => { if(!challenge) throw Error('Start a new code before signing in.'); const out = await request('/v1/auth/otp/verify','POST',{phone:$('phone').value,challengeId:challenge,code:$('code').value}); token = out.accessToken; org=''; sessionStorage.setItem('navig8r_access',token); sessionStorage.removeItem('navig8r_org'); await loadOrganizations(); });
$('signout').onclick = () => { sessionStorage.removeItem('navig8r_access'); sessionStorage.removeItem('navig8r_org'); location.reload(); };
async function loadOrganizations() {
 const me = await request('/v1/auth/me'); $('login').hidden = true; $('workspace').hidden = false;
 $('organization').replaceChildren(new Option('Select an organization',''));
 for(const organization of me.organizations) $('organization').append(new Option(organization.displayName,organization.id));
 if(!org && me.organizations.length===1) org=me.organizations[0].id;
 $('organization').value=org; if(org) await loadWorkspace();
}
$('organization').onchange=perform(async()=>{org=$('organization').value;sessionStorage.setItem('navig8r_org',org);$('shipments').replaceChildren();principal=undefined;$('roleManagement').hidden=true;$('compliance').hidden=true;if(org) await loadWorkspace();});
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
  if(s.status==='PENDING_RELEASE'&&principal.permissions.includes('payment.capture')){const b=document.createElement('button');b.textContent='Release payment';b.disabled=!s.paymentReady;b.onclick=perform(async()=>{await request('/ops/shipments/'+s.id+'/release','POST',{});await loadWorkspace();});row.append(b);}
  if(s.status==='PENDING_RELEASE'&&!s.podAcceptedAtUtcMs&&principal.permissions.includes('pod.accept')){const b=document.createElement('button');b.textContent='Accept POD';b.onclick=perform(async()=>{await request('/shipments/'+s.id+'/accept-pod','POST',{});await loadWorkspace();});row.append(b);}
  $('shipments').append(row);
 }
 if(!$('compliance').hidden) await loadKycQueue();
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
$('verifyKyc').onclick=perform(()=>recordReview($('carrierOrg').value.trim(),$('kycStatus').value));
if(token) perform(loadOrganizations)();
</script></body></html>`;
}
