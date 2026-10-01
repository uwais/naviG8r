/** The stylesheet of the /ops/beta page. Token names and values match the NaviG8r design system. */
export const opsConsoleBetaStyles = `
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
header select.field{width:auto;min-height:32px;padding:4px 8px;font-weight:600}
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
