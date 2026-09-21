/** Public shell; every data request is authenticated and authorized by the API. */
export function opsPortalHtml(options: { workflowOnly?: boolean } = {}): string {
  const workflowOnly = options.workflowOnly === true;
  const title = workflowOnly ? "NaviG8r shipments" : "NaviG8r operations";
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>
<style>body{font:16px system-ui;max-width:960px;margin:32px auto;padding:16px;color:#17243b}button,input,select{padding:10px;margin:6px}article{border:1px solid #ccd3de;border-radius:8px;padding:16px;margin:12px 0}label{display:block}#error{color:#a11212}small{display:block;color:#526079}</style></head><body>
<h1>${title}</h1><nav><a href="${workflowOnly ? "/admin" : "/workflow"}">${workflowOnly ? "Admin workspace" : "Shipment/POD workspace"}</a></nav><p id="error" role="alert"></p>
<section id="login"><label>Phone<input id="phone" autocomplete="tel"></label><button id="start">Send code</button><label>Verification code<input id="code" autocomplete="one-time-code"></label><button id="verify">Sign in</button></section>
<section id="workspace" hidden><label>Acting organization<select id="organization"><option value="">Select an organization</option></select></label><button id="signout">Sign out</button><p id="roles"></p><p id="access"></p><div id="shipments"></div>
<section id="roleManagement" hidden><h2>Membership roles</h2><label>User ID<input id="memberUser"></label><label>Organization ID<input id="memberOrg"></label><label>Roles (comma separated)<input id="memberRoles" placeholder="OPS,FINANCE"></label><button id="saveRoles">Save roles</button></section>
<section id="compliance" hidden><h2>Carrier compliance review</h2><label>Carrier organization ID<input id="carrierOrg"></label><label>Reason code<input id="reason" placeholder="DOCUMENTS_REVIEWED"></label><select id="kycStatus"><option>APPROVED</option><option>REJECTED</option></select><button id="verifyKyc">Record review</button></section></section>
<script>
const workflowOnly = ${workflowOnly};
let challenge = '', principal, token = sessionStorage.getItem('navig8r_access') || '', org = sessionStorage.getItem('navig8r_org') || '';
const $ = id => document.getElementById(id);
async function request(path, method = 'GET', body, extra = {}) {
 const headers = { 'content-type': 'application/json', ...extra };
 if (token) headers.authorization = 'Bearer ' + token;
 if (org) headers['x-organization-id'] = org;
 const response = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
 const out = await response.json(); if (!response.ok) throw Error(out.error || 'Request failed'); return out;
}
const perform = fn => async () => { $('error').textContent = ''; try { await fn(); } catch(e) { $('error').textContent = e.message; } };
$('start').onclick = perform(async () => { const out = await request('/v1/auth/otp/start','POST',{phone:$('phone').value}); challenge = out.challengeId; if(out.debugCode) $('code').value = out.debugCode; });
$('verify').onclick = perform(async () => { const out = await request('/v1/auth/otp/verify','POST',{phone:$('phone').value,challengeId:challenge,code:$('code').value}); token = out.accessToken; org=''; sessionStorage.setItem('navig8r_access',token); sessionStorage.removeItem('navig8r_org'); await loadOrganizations(); });
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
}
$('saveRoles').onclick=perform(async()=>{await request('/v1/roles','POST',{userId:$('memberUser').value,orgId:$('memberOrg').value,roles:$('memberRoles').value.split(',').map(s=>s.trim()).filter(Boolean)});await loadWorkspace();});
$('verifyKyc').onclick=perform(async()=>{await request('/v1/organizations/'+encodeURIComponent($('carrierOrg').value)+'/kyc','POST',{status:$('kycStatus').value},{'x-reason-code':$('reason').value});});
if(token) perform(loadOrganizations)();
</script></body></html>`;
}
