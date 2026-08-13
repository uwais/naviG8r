import { createRequire } from "module";

const require = createRequire(import.meta.url);
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  HeadingLevel, AlignmentType, BorderStyle, WidthType, ShadingType,
  LevelFormat, PageBreak, VerticalAlign, UnderlineType, Footer
} = require('docx');
const fs = require('fs');
const path = require('path');

// ── Palette ──────────────────────────────────────────────────────────────────
const C = {
  navy:   "0A2342", teal:   "1B8B8B", amber:  "E07B39",
  slate:  "4A5568", light:  "EBF4F4", muted:  "718096",
  white:  "FFFFFF", border: "CBD5E0", green:  "1E6E3E",
  red:    "B91C1C", purple: "5B21B6", yellow: "92400E",
  lightG: "F0FDF4", lightA: "FEF3C7", lightR: "FEF2F2", lightP: "F5F3FF",
};

// ── Primitives ────────────────────────────────────────────────────────────────
const PB = () => new Paragraph({ children: [new PageBreak()] });
const SP = (b=80,a=80) => new Paragraph({ spacing:{before:b,after:a}, children:[] });
const run = (text, opts={}) => new TextRun({ text, font:"Arial", size:22, color:C.slate, ...opts });
const brun = (text, color=C.navy) => new TextRun({ text, font:"Arial", size:22, bold:true, color });
const irun = (text, color=C.muted) => new TextRun({ text, font:"Arial", size:20, italics:true, color });

const para = (children, opts={}) => new Paragraph({ spacing:{before:60,after:60}, children, ...opts });
const body = (text, opts={}) => para([run(text, opts)]);
const italicNote = (prefix, text) => para([
  new TextRun({ text:prefix+" ", font:"Arial", size:20, bold:true, color:C.amber }),
  new TextRun({ text, font:"Arial", size:20, italics:true, color:C.amber }),
]);
const debunked = (text) => para([
  new TextRun({ text:"✗  REMOVED: ", font:"Arial", size:20, bold:true, color:C.red }),
  new TextRun({ text, font:"Arial", size:20, italics:true, color:C.red }),
]);
const validated = (text) => para([
  new TextRun({ text:"✓  VALIDATED: ", font:"Arial", size:20, bold:true, color:C.green }),
  new TextRun({ text, font:"Arial", size:20, italics:true, color:C.green }),
]);

const hr = (color=C.teal, size=6) => new Paragraph({
  spacing:{before:120,after:120},
  border:{ bottom:{ style:BorderStyle.SINGLE, size, color, space:1 } },
  children:[],
});
const thinHr = () => new Paragraph({
  spacing:{before:80,after:80},
  border:{ bottom:{ style:BorderStyle.SINGLE, size:2, color:C.border, space:1 } },
  children:[],
});

const h1 = (text) => new Paragraph({
  heading:HeadingLevel.HEADING_1, spacing:{before:320,after:160},
  children:[new TextRun({ text, bold:true, size:36, color:C.navy, font:"Arial" })],
});
const h2 = (text, color=C.teal) => new Paragraph({
  heading:HeadingLevel.HEADING_2, spacing:{before:240,after:100},
  children:[new TextRun({ text, bold:true, size:28, color, font:"Arial" })],
});
const h3 = (text) => new Paragraph({
  heading:HeadingLevel.HEADING_3, spacing:{before:180,after:80},
  children:[new TextRun({ text, bold:true, size:24, color:C.navy, font:"Arial" })],
});
const h4 = (text, color=C.teal) => new Paragraph({
  spacing:{before:140,after:60},
  children:[new TextRun({ text, bold:true, size:22, color, font:"Arial" })],
});

const bullet = (text, sub=false) => new Paragraph({
  numbering:{ reference:"bullets", level: sub?1:0 },
  spacing:{before:40,after:40},
  children:[run(text)],
});
const numbered = (text) => new Paragraph({
  numbering:{ reference:"numbers", level:0 },
  spacing:{before:40,after:40},
  children:[run(text)],
});
const checkItem = (text, done=false) => para([
  new TextRun({ text: done?"☑  ":"☐  ", font:"Arial", size:22, color: done?C.green:C.slate }),
  run(text),
]);

// ── Table helpers ─────────────────────────────────────────────────────────────
const cell = (children, width, shade=null, center=false) => new TableCell({
  width:{ size:width, type:WidthType.DXA },
  margins:{ top:100, bottom:100, left:120, right:120 },
  shading: shade ? { fill:shade, type:ShadingType.CLEAR } : undefined,
  verticalAlign: VerticalAlign.TOP,
  borders:{
    top:{style:BorderStyle.SINGLE,size:1,color:C.border},
    bottom:{style:BorderStyle.SINGLE,size:1,color:C.border},
    left:{style:BorderStyle.SINGLE,size:1,color:C.border},
    right:{style:BorderStyle.SINGLE,size:1,color:C.border},
  },
  children: (children.map ? children : [children]).map((child) => {
    if (typeof child === "string") {
      return cp(child, 20, C.slate, false, center);
    }
    return child;
  }),
});
const hcell = (text, width, bg=C.navy) => new TableCell({
  width:{ size:width, type:WidthType.DXA },
  margins:{ top:100, bottom:100, left:120, right:120 },
  shading:{ fill:bg, type:ShadingType.CLEAR },
  borders:{
    top:{style:BorderStyle.SINGLE,size:1,color:bg},
    bottom:{style:BorderStyle.SINGLE,size:1,color:bg},
    left:{style:BorderStyle.SINGLE,size:1,color:bg},
    right:{style:BorderStyle.SINGLE,size:1,color:bg},
  },
  children:[para([new TextRun({ text, bold:true, size:20, color:C.white, font:"Arial" })])],
});
const trow = (cells) => new TableRow({ children:cells });

const cp = (text, size=22, color=C.slate, bold=false, center=false) =>
  new Paragraph({ spacing:{before:40,after:40}, alignment:center?AlignmentType.CENTER:AlignmentType.LEFT,
    children:[new TextRun({ text, font:"Arial", size, color, bold })]});

const table = (headers, rows, widths, headerBg=C.navy) => new Table({
  width:{ size:9360, type:WidthType.DXA },
  columnWidths:widths,
  rows:[
    trow(headers.map((header, i) => hcell(header, widths[i], headerBg))),
    ...rows.map((row, rowIndex) => trow(row.map((value, i) => cell(
      Array.isArray(value) ? value : [cp(value, 20)],
      widths[i],
      rowIndex % 2 === 1 ? "F8FAFC" : null
    )))),
  ],
});

const metricTable = (rows) => table(
  ["Metric", "Definition", "Target / Guardrail"],
  rows,
  [2450, 4450, 2460],
  C.teal
);

// ── Section banner ────────────────────────────────────────────────────────────
const banner = (num, title, sub, bg=C.navy) => new Table({
  width:{ size:9360, type:WidthType.DXA }, columnWidths:[9360],
  rows:[trow([new TableCell({
    width:{ size:9360, type:WidthType.DXA },
    shading:{ fill:bg, type:ShadingType.CLEAR },
    borders:{ top:{style:BorderStyle.NONE}, bottom:{style:BorderStyle.NONE}, left:{style:BorderStyle.NONE}, right:{style:BorderStyle.NONE} },
    margins:{ top:160, bottom:160, left:200, right:200 },
    children:[
      new Paragraph({ spacing:{before:0,after:0}, children:[
        new TextRun({ text:`SECTION ${num}   `, size:18, font:"Arial", color:"7DD4C0", bold:true, characterSpacing:80 }),
        new TextRun({ text:title.toUpperCase(), size:26, font:"Arial", color:C.white, bold:true }),
      ]}),
      new Paragraph({ spacing:{before:40,after:0}, children:[
        new TextRun({ text:sub, size:18, font:"Arial", color:"A0C4BF", italics:true }),
      ]}),
    ],
  })])]
});

// ── Callout box ───────────────────────────────────────────────────────────────
const callout = (label, text, bg, border) => new Table({
  width:{ size:9360, type:WidthType.DXA }, columnWidths:[9360],
  rows:[trow([new TableCell({
    width:{ size:9360, type:WidthType.DXA },
    shading:{ fill:bg, type:ShadingType.CLEAR },
    borders:{
      top:{style:BorderStyle.SINGLE,size:12,color:border},
      bottom:{style:BorderStyle.NONE}, left:{style:BorderStyle.NONE}, right:{style:BorderStyle.NONE}
    },
    margins:{ top:120, bottom:120, left:160, right:160 },
    children:[
      para([new TextRun({ text:label, font:"Arial", size:18, bold:true, color:border }), run("  "+text, { size:21, color:C.slate })]),
    ],
  })])]
});

// ── Respondent info table ─────────────────────────────────────────────────────
const infoField = (label, w) => new TableCell({
  width:{ size:w, type:WidthType.DXA },
  borders:{ top:{style:BorderStyle.NONE}, bottom:{style:BorderStyle.SINGLE,size:4,color:C.teal}, left:{style:BorderStyle.NONE}, right:{style:BorderStyle.NONE} },
  margins:{ top:60, bottom:60, left:0, right:120 },
  children:[
    para([new TextRun({ text:label, size:18, font:"Arial", color:C.muted, bold:true })]),
    para([run(" ")]),
  ],
});

// ═══════════════════════════════════════════════════════════════════════════════
// DOCUMENT CONTENT
// ═══════════════════════════════════════════════════════════════════════════════

const children = [

// ── COVER ─────────────────────────────────────────────────────────────────────
SP(2000), SP(2000),
new Paragraph({ alignment:AlignmentType.CENTER, children:[
  new TextRun({ text:"NaviG8r", bold:true, size:72, font:"Arial", color:C.navy })
]}),
new Paragraph({ alignment:AlignmentType.CENTER, spacing:{before:60},
  children:[new TextRun({ text:"Product Requirements Document", size:36, font:"Arial", color:C.teal })] }),
new Paragraph({ alignment:AlignmentType.CENTER, spacing:{before:30},
  children:[new TextRun({ text:"Version 2.0  —  Ground-Truthed & Revised", size:26, font:"Arial", color:C.amber })] }),
new Paragraph({ alignment:AlignmentType.CENTER, spacing:{before:20},
  children:[new TextRun({ text:"B2B Freight Marketplace · India-First · Pre-Seed to Series A", size:22, font:"Arial", color:C.muted })] }),
SP(120), hr(),  SP(60),
new Paragraph({ alignment:AlignmentType.CENTER,
  children:[new TextRun({ text:"Uwais Khan  ·  NaviG8r / Gator Suite  ·  August 2026  ·  CONFIDENTIAL", size:18, font:"Arial", color:C.muted })] }),
PB(),

// ── REVISION NOTES ────────────────────────────────────────────────────────────
h1("Revision Notes — What Changed From v1.0"),
hr(),
body("This version incorporates findings from primary research (operator and MSME interviews), competitive analysis of Porter, fr8.in, BlackBuck, WheelsEye, and Vahak, and a thorough stress-test of v1.0's revenue model assumptions. Every claim that could not withstand scrutiny has been removed or replaced. The following is an explicit record of what was debunked, what was validated, and what was added."),
SP(),
h2("Removed from v1.0"),
debunked("PTL/LTL consolidation as a Phase 1–2 revenue line. Requires cross-docking infrastructure, kills the asset-light model, and puts NaviG8r in direct competition with VRL, Delhivery, and TCI on their strongest ground. Moved to Phase 3 evaluation only, after achieving corridor density."),
debunked("Carrier early-payment float as a standalone revenue product. The moment NaviG8r disburses before collecting, it has extended unsecured credit to the shipper. At scale, a 5% default rate on 1,500 trips/month produces ₹3.6 Cr in annual write-offs — more than the 1.5% carrier fee revenue that was supposed to justify it."),
debunked("Freight financing as a NaviG8r-owned product at early stage. Requires ₹15–25 Cr dedicated lending book, RBI NBFC license or co-lending arrangement, and 18+ months of clean default data to price risk. Not feasible pre-Series A."),
debunked("Advance payment norm from shippers as a 'solvable product problem.' Indian B2B payment culture is credit-first. Requiring advance payment loses 40–60% of otherwise-qualified shippers to traditional brokers who give credit on a handshake. This is a structural competitor advantage, not a UX problem."),
debunked("Porter as a competitor in intercity FTL. Porter's intercity service handles parcels up to 20kg. NaviG8r handles truck freight. These are different products. SMEs cited Porter by brand recognition, not actual product overlap."),
SP(),
h2("Validated from v1.0"),
validated("Commission-on-GTV marketplace model (8–10%) as primary revenue. Correct from day one."),
validated("Shipper-side TMS-lite as genuine white space. No incumbent — Porter, fr8.in, BlackBuck, Vahak — offers SME shippers an integrated TMS. This remains the clearest product differentiation."),
validated("AI SaaS as a defensible Layer 2 — but only after 18 months of transaction data accumulation and only if built on proprietary data and operational infrastructure, not as a language model wrapper."),
validated("ERP integration (Tally first, Zoho second) as the anti-leakage mechanism that Vahak never built. When a shipper's sales order automatically becomes a NaviG8r load, there is no moment to call a broker instead."),
validated("fr8.in as the real competitor — enterprise-skewed, thin on SME service, SME intercity FTL is NaviG8r's opening."),
validated("Informal shippers (no GST, cash-only) are not the Phase 1 target. They are the segment where NaviG8r's structural advantages are least useful and a broker's advantages are strongest."),
SP(),
h2("Added in v2.0"),
bullet("Embedded B2B credit via Rupifi partnership — replaces advance payment requirement entirely."),
bullet("NACH mandate (post-delivery auto-debit) for shippers not yet Rupifi-approved."),
bullet("Explicit fundraise requirements by phase with use-of-funds breakdown."),
bullet("Tightly defined pilot target customer — GST-registered, digitally active, ERP-using Delhi SME."),
bullet("Dispute reserve architecture — how the 48-hour window works operationally."),
bullet("Honest AI SaaS timing and data threshold before charging for it."),
bullet("Working capital referral to Credlix/Tata Capital (not own product) for freight receivables discounting."),
PB(),

// ── 1. EXECUTIVE SUMMARY ──────────────────────────────────────────────────────
banner("1", "Executive Summary", "What NaviG8r is, why it wins, and what v2.0 changes."),
h1("1. Executive Summary"),
body("NaviG8r is an India-first B2B freight marketplace for GST-registered SME shippers moving full-truckload intercity freight. The product combines broker-grade service with software-grade transparency: instant load creation, verified carrier matching, escrow-like payment control, live trip tracking, proof-of-delivery workflows, and lightweight transportation management tools for shippers who cannot buy or operate an enterprise TMS."),
body("The founding wedge is narrow by design: Delhi NCR SMEs that already issue GST invoices, already use Tally or Zoho, and already move repeat intercity FTL loads on predictable corridors. NaviG8r does not begin by trying to digitize every trucker or every informal shipper in India. It begins with the market segment where software reduces real leakage: businesses that have enough shipment volume to feel pain, enough digital maturity to adopt workflows, and enough compliance posture to support embedded credit and post-delivery automated collection."),
callout("CORE THESIS", "India's SME freight market does not need another open load board. It needs a managed marketplace with payment architecture, ERP-triggered demand capture, and operating discipline that makes the digital flow safer than calling a broker.", C.light, C.teal),
h2("Strategic Positioning"),
bullet("Phase 1 is a managed FTL marketplace with TMS-lite for shippers, not a carrier social network and not a financing company."),
bullet("The product earns primarily from marketplace commission on gross transaction value, not from float, spread lending, subscriptions, or PTL consolidation."),
bullet("Payment risk is solved through partner credit and mandate architecture: Track A Rupifi invoice credit, Track B NACH auto-debit after delivery."),
bullet("Defensibility comes from repeat corridor liquidity, ERP integration, verified carrier performance history, and proprietary shipment operations data."),
bullet("AI is a later monetization layer built on accumulated execution data; it is not the reason the first customer signs."),
h2("Non-Negotiable Product Principles"),
numbered("Keep the model asset-light until density proves a lane-specific operational reason to add assets or consolidation infrastructure."),
numbered("Never pay carriers before shipper collection unless the transaction is explicitly funded by a partner credit product or insured structure."),
numbered("Design for trust and dispute resolution before designing for scale; failed POD and payment experiences destroy marketplace liquidity."),
numbered("Make the shipper workflow faster than calling a broker and make the carrier workflow no more complex than receiving a confirmed load and getting paid."),
numbered("Use human operations deliberately in Phase 1; automate only after the workflow has enough observed repetition to justify productization."),
SP(),
table(
  ["Decision", "v2.0 Direction", "Reason"],
  [
    ["Initial market", "GST-registered Delhi NCR SME shippers", "The segment can adopt ERP-linked workflows, supports formal payment rails, and has repeat FTL pain."],
    ["Payment model", "Rupifi credit first; NACH fallback", "Avoids asking shippers for advance payment while preventing NaviG8r from becoming the lender."],
    ["Carrier acquisition", "Verified fleet owners and lane-specialist operators", "Quality and reliability matter more than raw truck count in early liquidity formation."],
    ["AI timing", "Data-first; charge only after sufficient transaction history", "Without proprietary execution data, AI is undifferentiated and not defensible."],
  ],
  [2200, 3100, 4060]
),
PB(),

// ── 2. MARKET & COMPETITIVE LANDSCAPE ─────────────────────────────────────────
banner("2", "Market & Competitive Landscape", "Where NaviG8r fits among brokers, load boards, FTL platforms, and SME software."),
h1("2. Market & Competitive Landscape"),
body("India's freight market remains relationship-heavy, fragmented, and credit-driven. The largest opportunity for NaviG8r is not the entire logistics market; it is the repeat intercity FTL workflow where SME shippers rely on brokers because brokers bundle trust, credit, and exception handling. Existing digital platforms solve only parts of that bundle."),
callout("MARKET REALITY", "The broker is not winning because the broker has better software. The broker is winning because the broker provides credit, takes phone calls, handles disputes, and knows which truck will actually show up. NaviG8r must digitize the bundle, not merely post loads online.", C.lightA, C.amber),
h2("Competitive Landscape"),
table(
  ["Player", "Core Strength", "Gap NaviG8r Can Exploit"],
  [
    ["Traditional brokers", "Trust, credit, local carrier relationships, exception handling", "Opaque pricing, leakage, no analytics, no system-of-record, limited repeat workflow visibility."],
    ["fr8.in", "FTL execution, enterprise credibility, transporter network", "More enterprise-skewed; less emphasis on SME TMS-lite and ERP-led shipper workflow."],
    ["BlackBuck", "Large trucker network, FASTag/fuel/driver ecosystem, freight marketplace history", "Carrier-first orientation; not built as an SME shipper operating system."],
    ["WheelsEye", "Fleet owner tools, GPS, FASTag, fuel, compliance stack", "Carrier and fleet SaaS focus; shipper-side managed freight workflow remains open."],
    ["Vahak", "Load discovery and marketplace network effects", "Load-board leakage risk; weak lock-in unless it owns shipper workflow and payment rails."],
    ["Porter", "Strong SME brand recall, intracity execution, app simplicity", "Parcel and city logistics orientation; intercity FTL is not Porter's core product."],
  ],
  [1800, 3000, 4560],
  C.navy
),
SP(),
h2("Segment Attractiveness"),
table(
  ["Segment", "Pain Intensity", "Digital Readiness", "Fit for Phase 1"],
  [
    ["Informal cash shippers", "High", "Low", "Poor fit. Broker advantage is strongest because cash, relationship credit, and informal settlement dominate."],
    ["Micro shippers with occasional freight", "Medium", "Medium", "Weak fit. Low repeat volume makes acquisition cost difficult to recover."],
    ["GST-registered SMEs with repeat FTL", "High", "High", "Best fit. Repeat loads, formal invoices, and ERP usage create a product wedge."],
    ["Large enterprises", "High", "High", "Later fit. Procurement cycles are slower and incumbents already serve many lanes."],
    ["Carriers and fleet owners", "Medium", "Medium", "Supply-side fit only after committed demand exists; carriers follow reliable payment and load density."],
  ],
  [2250, 2100, 2100, 2910],
  C.teal
),
callout("OPENING", "The white space is not generic freight matching. It is SME shipper workflow ownership: load creation from ERP, managed carrier assignment, proof-of-delivery control, transparent billing, and payment collection that does not depend on advance payment.", C.lightG, C.green),
h2("Market Entry Constraints"),
bullet("Credit norms are structural. Requiring advance payment removes too much addressable demand."),
bullet("Trust is local and lane-specific. Early liquidity must be built corridor by corridor, not nationally by logo count."),
bullet("Carrier onboarding is necessary but insufficient. Without committed shipper demand, carrier supply becomes stale and unresponsive."),
bullet("Enterprise logistics platforms may look impressive but leave a service gap for SMEs who cannot staff a logistics control tower."),
bullet("Load-board models face disintermediation once shipper and carrier discover each other unless workflow, payment, and service remain inside the platform."),
PB(),

// ── 3. TARGET CUSTOMER ────────────────────────────────────────────────────────
banner("3", "Target Customer", "The exact customer NaviG8r should serve first."),
h1("3. Target Customer"),
h2("Primary ICP: GST-Registered Delhi SME Shipper"),
body("The Phase 1 customer is a GST-registered SME shipper in Delhi NCR moving repeat full-truckload intercity freight. The company is large enough to suffer from freight opacity but too small to buy, configure, and operate an enterprise transportation management system. It likely uses Tally today, may use Zoho, and coordinates logistics through a founder, operations manager, accountant, or dispatch coordinator rather than a dedicated logistics technology team."),
table(
  ["Attribute", "Target Definition", "Why It Matters"],
  [
    ["Compliance posture", "GST-registered, invoice-driven, bank-account settlement", "Required for Rupifi underwriting, NACH mandates, clean billing, and dispute audit trails."],
    ["Shipment pattern", "Repeat FTL on known lanes, at least 8–30 loads/month", "Creates enough frequency for marketplace liquidity and workflow habit formation."],
    ["Digital maturity", "Uses Tally or Zoho; comfortable with WhatsApp, UPI, email invoices", "Enables ERP-triggered load creation and reduces adoption friction."],
    ["Pain profile", "Broker dependence, opaque rates, missed dispatches, delayed POD, invoice mismatch", "These are solvable through managed workflow plus payment architecture."],
    ["Decision maker", "Founder, operations head, finance owner, or family-business second generation", "Needs trust narrative and measurable savings, not only a feature demo."],
  ],
  [2100, 3500, 3760],
  C.navy
),
h2("Excluded From Phase 1"),
bullet("No-GST cash-only shippers whose existing broker relationship is optimized around informality."),
bullet("Occasional shippers who do not have enough repeat load volume to justify customer success effort."),
bullet("Large enterprise shippers requiring complex procurement, EDI, multi-plant integrations, and custom SLAs before product-market fit is proven."),
bullet("PTL and parcel customers expecting hub-and-spoke consolidation, warehousing, or last-mile delivery."),
h2("Pilot Respondent Profile Template"),
new Table({
  width:{ size:9360, type:WidthType.DXA },
  columnWidths:[2340,2340,2340,2340],
  rows:[
    trow([
      infoField("Company / Brand", 2340),
      infoField("Monthly FTL Loads", 2340),
      infoField("Current Broker Count", 2340),
      infoField("ERP / Accounting System", 2340),
    ]),
    trow([
      infoField("Top Lanes", 2340),
      infoField("Payment Terms", 2340),
      infoField("POD Delay Pain", 2340),
      infoField("Pilot Owner", 2340),
    ]),
  ],
}),
h2("Customer Jobs To Be Done"),
numbered("Create and confirm an intercity FTL load without making five broker calls."),
numbered("Know the truck, driver, expected arrival, and price before dispatch."),
numbered("Receive proof of delivery quickly enough to invoice or close internal records."),
numbered("Avoid surprise accessorials, invoice mismatch, and unclear detention claims."),
numbered("Get credit terms without relying on informal broker trust."),
numbered("Build a repeatable freight history by lane, carrier, plant, SKU class, and customer."),
callout("ADOPTION MOTION", "The first sale should not be positioned as freight technology. It should be positioned as a safer, clearer way to move the same repeat loads the shipper already moves every month.", C.light, C.teal),
PB(),

// ── 4. PAYMENT ARCHITECTURE ───────────────────────────────────────────────────
banner("4", "Payment Architecture", "Track A Rupifi, Track B NACH, and dispute reserve mechanics."),
h1("4. Payment Architecture"),
body("Payment architecture is the most important v2.0 correction. NaviG8r cannot require universal advance payment and cannot become the early-stage lender. The product must let shippers preserve familiar credit behavior while ensuring NaviG8r does not take unsecured balance-sheet risk."),
h2("Track A: Rupifi Embedded Credit"),
body("Track A is the preferred payment flow. Eligible shippers receive embedded B2B credit through Rupifi or an equivalent partner. NaviG8r stays the marketplace and workflow layer; the partner underwrites and funds credit. Shipper credit approval happens during onboarding or before first credit-backed load confirmation."),
table(
  ["Step", "Actor", "Requirement"],
  [
    ["1. Credit eligibility", "Rupifi + NaviG8r", "Collect GST, PAN, bank statement or surrogate data, invoice history, and basic business KYC."],
    ["2. Load booking", "Shipper", "Customer selects credit-backed payment option if available credit limit covers expected freight plus fees."],
    ["3. Carrier assignment", "NaviG8r Ops", "Only confirmed credit-backed loads proceed to final carrier dispatch without advance collection."],
    ["4. Delivery and POD", "Carrier + Shipper", "POD starts the dispute window and triggers invoice finalization."],
    ["5. Settlement", "Rupifi + NaviG8r", "Partner handles shipper repayment terms; NaviG8r receives platform settlement per commercial arrangement."],
  ],
  [1400, 2300, 5660],
  C.green
),
callout("TRACK A RULE", "If partner credit funds the transaction, NaviG8r can preserve shipper credit terms without using its own balance sheet. This is the default path for qualified repeat shippers.", C.lightG, C.green),
h2("Track B: NACH Post-Delivery Auto-Debit"),
body("Track B is the fallback for shippers not yet approved for Rupifi or whose approved limit is insufficient. The shipper signs a NACH mandate before load execution. NaviG8r does not debit before delivery; it debits after POD acceptance or after the dispute window closes."),
table(
  ["Step", "Trigger", "System Behavior"],
  [
    ["Mandate setup", "Before first Track B load", "Collect authorization, bank details, mandate cap, and customer consent text."],
    ["Load confirmation", "Before dispatch", "Validate mandate active status and cap against estimated freight amount."],
    ["Delivery event", "POD uploaded", "Notify shipper and open 48-hour dispute window."],
    ["No dispute", "48 hours after POD", "Initiate NACH debit for final invoice amount."],
    ["Dispute raised", "Within 48 hours", "Hold debit, route to operations review, and release debit only after adjustment or resolution."],
  ],
  [1900, 2500, 4960],
  C.amber
),
h2("Dispute Reserve Architecture"),
body("The dispute reserve is not a lending product. It is an operational hold mechanism. The platform should not release full final settlement until delivery is verified and the shipper has had a defined window to raise a legitimate issue. The reserve must be predictable, documented, and small enough not to destroy carrier trust."),
bullet("Default dispute window: 48 hours after POD upload or delivery confirmation."),
bullet("Eligible dispute reasons: shortage, damage, late delivery with documented SLA impact, wrong vehicle, detention disagreement, invoice mismatch."),
bullet("Non-eligible reasons: buyer's remorse, market rate changes after booking, undocumented verbal side agreements, and disputes raised after window expiry."),
bullet("Ops outcome: approve debit, adjust invoice, request evidence, split liability, or escalate for leadership approval."),
bullet("Carrier communication: show expected settlement date and dispute status so the carrier is not left guessing."),
h2("Payment Risk Controls"),
table(
  ["Risk", "Control", "Owner"],
  [
    ["Shipper default", "Use partner credit or mandate-backed debit; cap exposure by customer and lane.", "Finance + Risk"],
    ["POD fraud", "Geo-tagged upload, driver OTP, receiver stamp/photo, and exception review.", "Ops"],
    ["Carrier no-show", "Carrier score, lane history, backup pool, and penalty policy.", "Supply Ops"],
    ["Invoice mismatch", "Rate card lock at booking; accessorial approval workflow.", "Product + Ops"],
    ["Chargeback or mandate failure", "Fallback collection workflow and temporary account hold.", "Finance"],
  ],
  [2200, 4760, 2400],
  C.navy
),
PB(),

// ── 5. REVENUE MODEL ──────────────────────────────────────────────────────────
banner("5", "Revenue Model", "How NaviG8r earns without breaking trust or taking hidden credit risk."),
h1("5. Revenue Model"),
body("NaviG8r's revenue model must stay simple until marketplace liquidity is stable. The primary revenue line is commission on gross transaction value. Secondary revenue lines should attach to real workflow value and should not require NaviG8r to own credit, trucks, warehouses, or PTL infrastructure before there is proof of density."),
h2("Revenue Lines"),
table(
  ["Revenue Line", "Timing", "Notes"],
  [
    ["Marketplace commission", "Day one", "8–10% of GTV as the core monetization engine. Rate can vary by lane, volume, vehicle type, and service level."],
    ["Managed service fee", "Pilot to Phase 2", "Small fee for dedicated ops handling, SLA reporting, dispute management, and premium support for repeat shippers."],
    ["ERP / TMS-lite subscription", "After repeat usage", "Only charge after customers rely on dashboard, reports, and ERP-triggered load creation."],
    ["Working capital referral", "Phase 2", "Referral or revenue share with Credlix/Tata Capital for shipper receivables discounting; NaviG8r does not lend."],
    ["AI decision support SaaS", "After 18+ months data", "Lane pricing, carrier reliability scoring, exception prediction, and procurement insights built on proprietary transaction data."],
    ["PTL/LTL consolidation", "Phase 3 evaluation", "Only evaluate after corridor density and operational economics justify infrastructure or partnerships."],
  ],
  [2300, 1900, 5160],
  C.teal
),
h2("Do Not Monetize Early"),
debunked("Do not monetize carrier early-payment float as a standalone revenue line. It creates unsecured shipper exposure and can wipe out the revenue it claims to generate."),
debunked("Do not launch NaviG8r-owned freight financing pre-Series A. It requires capital, underwriting infrastructure, regulatory clarity, and loss data NaviG8r will not yet have."),
debunked("Do not sell AI as a generic chatbot or generic rate prediction tool before there is proprietary data density."),
debunked("Do not launch PTL/LTL consolidation as a Phase 1–2 revenue line because it adds infrastructure complexity and moves NaviG8r into incumbent territory."),
h2("Unit Economics Guardrails"),
table(
  ["Metric", "Target", "Reason"],
  [
    ["Take rate", "8–10% blended", "Enough gross margin for managed operations without shocking SME pricing."],
    ["Ops cost per load", "Declines each cohort", "Manual service is acceptable only if playbooks convert into product automation."],
    ["Dispute rate", "< 5% of delivered loads", "High disputes indicate poor carrier quality, unclear pricing, or weak POD workflow."],
    ["Repeat load ratio", "> 60% by month 6 in pilot cohort", "Repeat use is the strongest proof that NaviG8r is replacing broker behavior."],
    ["Payment failure rate", "< 3% for NACH loads", "Higher failures mean Track B underwriting and mandate thresholds are too loose."],
  ],
  [2600, 2300, 4460],
  C.navy
),
callout("MODEL DISCIPLINE", "Revenue should follow trust. If a revenue line requires NaviG8r to hide risk, own capital exposure, or add infrastructure before density, it belongs later.", C.lightP, C.purple),
PB(),

// ── 6. PRODUCT REQUIREMENTS ───────────────────────────────────────────────────
banner("6", "Product Requirements", "6A shipper, 6B carrier, and 6C admin control requirements."),
h1("6. Product Requirements"),
body("The product is split into three operating surfaces: shipper experience, carrier experience, and admin control. The first production version should be narrow, reliable, and operations-friendly. The admin layer is as important as the customer app because early marketplace quality will depend on controlled workflows and exception handling."),
h2("6A. Shipper Product Requirements"),
callout("SHIPPER PROMISE", "Create a repeat FTL load, get a reliable truck, track status, receive POD, and settle payment without losing the credit behavior SMEs expect.", C.light, C.teal),
table(
  ["Requirement", "Priority", "Acceptance Criteria"],
  [
    ["Account onboarding", "P0", "Capture company profile, GST, billing contact, lane preferences, payment track eligibility, and ERP status."],
    ["Load creation", "P0", "Shipper can create FTL load with origin, destination, material type, weight, vehicle type, pickup window, delivery SLA, and special instructions."],
    ["Repeat load templates", "P0", "Shipper can reuse prior lane, vehicle, consignor, consignee, material, and payment settings."],
    ["Quote confirmation", "P0", "Show confirmed price or operations-confirmed quote with included/excluded charges before booking."],
    ["Payment track display", "P0", "Show Rupifi credit, NACH mandate, or advance/manual exception status before dispatch confirmation."],
    ["Live shipment tracking", "P1", "Display assigned truck, driver contact, milestones, ETA, and exceptions."],
    ["POD workflow", "P0", "Shipper receives POD upload notification and can accept, dispute, or request clarification within 48 hours."],
    ["Invoice and documents", "P0", "Provide downloadable invoice, consignment note, POD, and adjustment record."],
    ["ERP integration", "P1", "Tally-first import/export or connector flow to turn sales orders into draft loads and push freight invoice records back."],
    ["Analytics dashboard", "P1", "Show lane spend, carrier performance, delay reasons, dispute history, and payment status."],
  ],
  [2550, 1200, 5610],
  C.navy
),
h3("Shipper UX Notes"),
bullet("Keep first load creation conversational and assisted; do not expose enterprise logistics terminology too early."),
bullet("Use WhatsApp and email notifications alongside dashboard notifications during Phase 1."),
bullet("Make credit status visible but not confusing: Approved, Pending, Mandate Required, or Manual Review."),
bullet("Every price confirmation must state whether loading, unloading, detention, toll, border, and insurance charges are included or excluded."),
h2("6B. Carrier Product Requirements"),
callout("CARRIER PROMISE", "Verified loads, clear pickup instructions, transparent documents, and predictable payment status.", C.lightG, C.green),
table(
  ["Requirement", "Priority", "Acceptance Criteria"],
  [
    ["Carrier onboarding", "P0", "Capture owner profile, GST/PAN where applicable, bank account, vehicle documents, insurance, permit data, and lane preferences."],
    ["Vehicle verification", "P0", "Admin can verify RC, fitness, insurance, permit, pollution certificate, and vehicle capacity."],
    ["Load offer", "P0", "Carrier receives load details, pickup window, commodity, expected freight, payment timing, and special instructions before acceptance."],
    ["Driver assignment", "P0", "Carrier can assign driver name, phone, vehicle number, and backup contact."],
    ["Trip milestones", "P0", "Driver or ops can update arrived pickup, loaded, departed, in transit, arrived delivery, unloaded, and POD uploaded."],
    ["POD upload", "P0", "Carrier can upload photo/PDF POD with receiver stamp or signature and optional damage/shortage evidence."],
    ["Payment status", "P0", "Carrier sees expected settlement, dispute hold, adjustment, and paid status."],
    ["Performance score", "P1", "System calculates acceptance reliability, no-show rate, on-time pickup, on-time delivery, dispute rate, and document quality."],
    ["Support escalation", "P1", "Carrier can raise pickup delay, unloading delay, route issue, rate dispute, or payment question."],
  ],
  [2550, 1200, 5610],
  C.green
),
h3("Carrier UX Notes"),
bullet("Do not require carriers to learn a complex dashboard before they receive value; WhatsApp-first workflows are acceptable in Phase 1."),
bullet("Use admin-assisted updates where driver app adoption is weak, but record every status change in the system of record."),
bullet("Payment transparency is the strongest carrier retention lever; show why money is held and when it is expected to move."),
h2("6C. Admin Console & Control Banners"),
callout("ADMIN PROMISE", "The admin console is the operating cockpit: it must expose risk, exceptions, payment state, and marketplace quality before customers feel failure.", C.lightA, C.amber),
table(
  ["Admin Area", "Priority", "Requirement"],
  [
    ["Load control tower", "P0", "View all loads by status, lane, shipper, carrier, payment track, pickup date, and exception state."],
    ["Banner system", "P0", "Show high-visibility banners for Credit Pending, Mandate Missing, Carrier Docs Expired, Pickup At Risk, POD Pending, Dispute Open, Debit Failed, and Payment Hold."],
    ["Manual matching", "P0", "Ops can assign, reassign, or backup carriers with reason codes and audit trail."],
    ["Pricing controls", "P0", "Ops can lock quote, add accessorials, approve adjustments, and record customer-visible reason."],
    ["Payment operations", "P0", "Finance can see Rupifi status, NACH mandate state, debit attempts, settlement holds, and failed collections."],
    ["Dispute workflow", "P0", "Ops can collect evidence, pause debit, adjust invoice, approve resolution, and communicate outcome."],
    ["Carrier compliance", "P0", "Track document expiry, verification state, blacklists, warnings, and preferred-lane status."],
    ["Customer success notes", "P1", "Record shipper preferences, broker replacement objections, rate sensitivity, and renewal risk."],
    ["Analytics exports", "P1", "Export lane, GTV, take rate, dispute, delay, and payment data for fundraising and operating reviews."],
  ],
  [2550, 1200, 5610],
  C.amber
),
h3("Admin Banner Rules"),
bullet("Banners must be state-driven and dismissible only with a reason code where risk remains."),
bullet("Payment-risk banners must block dispatch when the load has no approved credit, active mandate, advance collection, or explicit leadership override."),
bullet("Carrier compliance banners must block assignment if critical documents are expired or unverified."),
bullet("POD Pending and Dispute Open banners must remain visible on load, shipper, carrier, and finance views."),
PB(),

// ── 7. PLATFORM ARCHITECTURE & NFR ────────────────────────────────────────────
banner("7", "Platform Architecture & NFR", "Product architecture, integration boundaries, and non-functional requirements."),
h1("7. Platform Architecture & NFR"),
body("NaviG8r should be architected as a transaction system of record for SME FTL freight. The platform must keep load state, payment state, carrier compliance state, and document state consistent. Early operations may be manual, but the data model should assume these workflows become automated."),
h2("Core System Components"),
table(
  ["Component", "Responsibilities", "Notes"],
  [
    ["Shipper portal", "Load creation, quote approval, tracking, POD review, invoice download, analytics", "Responsive web first; mobile-friendly for owner/operators."],
    ["Carrier interface", "Load acceptance, driver assignment, milestone updates, POD upload, payment status", "WhatsApp-assisted plus lightweight web/app flow."],
    ["Admin console", "Matching, pricing, compliance, payment, disputes, banners, analytics", "Highest priority internal tool for Phase 1 reliability."],
    ["Payment service", "Rupifi state, NACH mandate, debit attempts, settlement holds, invoice finalization", "Keep partner-specific adapters isolated."],
    ["Document service", "POD, invoice, consignment note, carrier docs, evidence files", "All documents must attach to load and audit trail."],
    ["Integration layer", "Tally, Zoho, WhatsApp, SMS/email, maps/tracking, credit partner APIs", "Build adapter pattern to avoid hard-coding partner assumptions."],
    ["Analytics warehouse", "GTV, take rate, lane performance, carrier scores, dispute patterns, credit behavior", "Initial exports can be simple but schema should be clean."],
  ],
  [2200, 4300, 2860],
  C.navy
),
h2("Load State Machine"),
numbered("Draft"),
numbered("Payment Ready"),
numbered("Quote Confirmed"),
numbered("Carrier Assigned"),
numbered("Pickup Scheduled"),
numbered("Loaded"),
numbered("In Transit"),
numbered("Delivered"),
numbered("POD Uploaded"),
numbered("Dispute Window Open"),
numbered("Invoice Finalized"),
numbered("Debit / Settlement In Progress"),
numbered("Closed"),
h2("Non-Functional Requirements"),
table(
  ["NFR", "Requirement", "Rationale"],
  [
    ["Availability", "99.5% for customer-facing portal during pilot; admin console must degrade gracefully.", "Freight workflows tolerate some manual backup but not lost state."],
    ["Auditability", "Every pricing, payment, dispute, assignment, and status override requires actor, timestamp, and reason.", "Trust and finance controls require complete traceability."],
    ["Security", "Role-based access for shipper, carrier, ops, finance, admin; protect KYC and bank data.", "Payment and compliance data are sensitive."],
    ["Data retention", "Retain shipment, invoice, POD, and dispute records for statutory and commercial review.", "Required for GST, partner underwriting, and customer reporting."],
    ["Performance", "Load list and admin filters should respond within two seconds for pilot-scale data.", "Ops teams need fast control tower decisions."],
    ["Resilience", "Payment and notification retries must be idempotent and observable.", "Duplicate debits and missing customer messages are unacceptable."],
    ["Observability", "Log partner API failures, notification failures, mandate state changes, and state-machine transitions.", "Debugging early marketplace operations depends on visible system events."],
  ],
  [1900, 4450, 3010],
  C.teal
),
callout("ARCHITECTURE RULE", "The platform may start with manual operations, but no critical workflow should live only in someone's WhatsApp chat. If it affects customer trust, carrier payment, or investor metrics, it must enter the system of record.", C.lightP, C.purple),
PB(),

// ── 8. AI & DATA STRATEGY ─────────────────────────────────────────────────────
banner("8", "AI & Data Strategy", "How AI becomes defensible after operational data density exists."),
h1("8. AI & Data Strategy"),
body("AI is not a Phase 1 headline product. It is a later intelligence layer built on NaviG8r's proprietary shipment execution data: lane quotes, accepted prices, carrier reliability, pickup delays, POD quality, dispute reasons, payment behavior, seasonality, and shipper preferences. The initial data strategy must make that future possible."),
h2("Data Assets To Capture From Day One"),
table(
  ["Data Asset", "Examples", "Future Use"],
  [
    ["Lane pricing history", "Origin, destination, vehicle type, commodity, quote, accepted rate, date", "Dynamic pricing, quote confidence, procurement benchmarking."],
    ["Carrier performance", "Acceptance, no-show, delay, POD quality, dispute rate, payment incidents", "Carrier scoring, matching, risk prediction."],
    ["Shipper behavior", "Load frequency, payment track, dispute rate, lane repeat, quote acceptance", "Credit routing, churn prediction, account expansion."],
    ["Operational exceptions", "Pickup delay, unloading delay, route issue, document issue, debit failure", "Exception prediction and workflow automation."],
    ["Document intelligence", "POD fields, stamps, signatures, shortages, damage evidence", "POD validation and invoice automation."],
  ],
  [2200, 3900, 3260],
  C.navy
),
h2("AI Use Cases By Maturity"),
table(
  ["Maturity", "Use Case", "Launch Condition"],
  [
    ["Phase 1", "Ops assist summaries, dispute categorization, document extraction", "Human review mandatory; no customer-facing automated decisions."],
    ["Phase 2", "Lane pricing guidance and carrier shortlist recommendations", "Enough repeat loads by lane and vehicle type to measure accuracy."],
    ["Phase 2", "Exception prediction", "Historical event data with clear labels for delay, no-show, payment failure, and dispute."],
    ["Phase 3", "Shipper procurement intelligence SaaS", "18+ months of data, multi-customer lane benchmarks, and proven willingness to pay."],
    ["Phase 3", "Autonomous matching recommendations", "Carrier score reliability and override audit trail prove model decisions outperform manual ops."],
  ],
  [1800, 4300, 3260],
  C.purple
),
h2("AI Monetization Rules"),
bullet("Do not sell AI before there is measurable workflow value beyond generic language-model output."),
bullet("Charge for procurement intelligence only when the customer can see savings, reliability improvement, or internal productivity gains."),
bullet("Keep human override and explanation available for pricing, matching, and dispute recommendations."),
bullet("Use proprietary NaviG8r transaction data as the moat; public freight indices and generic LLMs are not enough."),
bullet("Protect customer-specific rate data. Benchmarking must be aggregated, anonymized, and contractually safe."),
callout("AI THESIS", "The first AI moat is disciplined data capture. Every load moved before the AI layer exists should make the later model smarter.", C.lightP, C.purple),
PB(),

// ── 9. PRODUCT ROADMAP ────────────────────────────────────────────────────────
banner("9", "Product Roadmap", "Sequenced build plan from pilot to defensible marketplace."),
h1("9. Product Roadmap"),
body("The roadmap prioritizes risk retirement: payment risk, shipper workflow adoption, carrier reliability, repeat lane density, and investor-grade metrics. Each phase should produce evidence for the next financing or expansion decision."),
h2("Roadmap Phases"),
table(
  ["Phase", "Product Scope", "Exit Criteria"],
  [
    ["Pilot", "Manual-assisted shipper portal, admin console, carrier verification, Rupifi/NACH payment workflow, POD and dispute flow", "Repeat loads from initial Delhi SME cohort; successful payment collection; carrier settlement trust."],
    ["Phase 1", "Tally-first integration, repeat load templates, lane dashboards, improved tracking, structured carrier score", "60%+ repeat load ratio, controlled dispute rate, reliable corridor liquidity."],
    ["Phase 2", "Zoho integration, working capital referrals, pricing guidance, stronger analytics, expanded cities/lanes", "Evidence of scalable acquisition, lower ops cost per load, partner-credit operating history."],
    ["Phase 3", "AI SaaS, procurement intelligence, possible PTL/LTL corridor experiments, deeper automation", "18+ months transaction data, defensible models, corridor density sufficient for new revenue lines."],
  ],
  [1700, 4600, 3060],
  C.navy
),
h2("Pilot Build Checklist"),
checkItem("Shipper account onboarding with GST and billing details.", true),
checkItem("Load creation and repeat load template.", true),
checkItem("Manual quote and carrier assignment workflow.", true),
checkItem("Carrier document verification and compliance state.", true),
checkItem("Rupifi eligibility capture and partner status field.", false),
checkItem("NACH mandate setup and active mandate validation.", false),
checkItem("POD upload, 48-hour dispute window, and invoice finalization.", false),
checkItem("Admin banners for payment, compliance, pickup, POD, dispute, and debit failure.", false),
checkItem("Basic lane, GTV, take-rate, delay, dispute, and repeat-use metrics export.", false),
h2("Roadmap Sequencing Logic"),
bullet("Build the admin console early because manual operations need a clean system of record."),
bullet("Build payment controls before scaling carrier supply because dispatch without payment readiness creates hidden credit exposure."),
bullet("Build ERP integration after repeat load creation proves that shippers will use NaviG8r for their normal lanes."),
bullet("Build AI only after labels and outcomes are sufficiently clean to train or evaluate useful recommendations."),
PB(),

// ── 10. FUNDRAISING REQUIREMENTS ──────────────────────────────────────────────
banner("10", "Fundraising Requirements", "Capital needs, proof points, and use of funds by phase."),
h1("10. Fundraising Requirements"),
body("NaviG8r's fundraising narrative should be tied to evidence rather than market size alone. The business is attractive if it proves that SME shippers will move repeat FTL loads through a managed digital workflow, that payment risk can be controlled through partner architecture, and that carrier liquidity improves lane by lane."),
h2("Pre-Seed Requirements"),
table(
  ["Requirement", "Evidence Needed", "Why Investors Care"],
  [
    ["Clear ICP", "Named Delhi NCR SME segment with interview notes and pilot commitments", "Shows the company is not boiling the ocean."],
    ["Payment architecture", "Rupifi/NACH workflow validated with partner conversations and pilot-ready process", "Retires the largest v1.0 risk."],
    ["Pilot marketplace", "Initial shipper demand and verified carrier pool on selected lanes", "Shows supply and demand can be coordinated."],
    ["Founder-led sales motion", "Repeatable pitch, objections, pricing, and onboarding checklist", "Shows early acquisition can be learned and scaled."],
    ["Operating dashboard", "GTV, loads, take rate, disputes, payment state, repeat use", "Creates investor-grade visibility."],
  ],
  [2600, 3900, 2860],
  C.green
),
h2("Seed / Series A Requirements"),
table(
  ["Milestone", "Target Proof Point", "Use of Funds"],
  [
    ["Seed", "Repeat load retention, stable take rate, low payment failure, trusted carrier pool", "Product team, operations playbook, payment integrations, lane expansion, customer success."],
    ["Seed extension", "Lower ops cost per load and broader ERP workflow adoption", "Automation, analytics, more city pairs, partner-credit optimization."],
    ["Series A", "Multi-city repeatable acquisition and proprietary data advantage", "Scale go-to-market, advanced matching, AI/data products, enterprise-adjacent accounts."],
  ],
  [2100, 4100, 3160],
  C.navy
),
h2("Use-of-Funds Framework"),
table(
  ["Category", "Pre-Seed Focus", "Seed Focus"],
  [
    ["Product & Engineering", "Core workflows, admin console, payment state, document flow", "ERP integrations, analytics, automation, AI-ready data foundation."],
    ["Operations", "Manual control tower, carrier verification, dispute process", "Regional ops playbooks and lane density management."],
    ["Partnerships", "Rupifi, NACH provider, WhatsApp/SMS, mapping/tracking", "Working capital referrals, broader credit/risk partners."],
    ["Sales & CS", "Founder-led shipper acquisition and onboarding", "Repeatable SME acquisition motion and retention programs."],
    ["Risk & Finance", "Payment controls and collection workflows", "Underwriting analytics, payment optimization, audit readiness."],
  ],
  [2200, 3580, 3580],
  C.teal
),
callout("FUNDRAISING MESSAGE", "Do not pitch NaviG8r as 'Uber for trucks' or as an AI freight company. Pitch it as the managed SME freight operating layer that solves the broker bundle with software, payments, and corridor discipline.", C.light, C.teal),
PB(),

// ── 11. RISK REGISTER ─────────────────────────────────────────────────────────
banner("11", "Risk Register", "The known risks and the controls required before scaling."),
h1("11. Risk Register"),
body("The following risks should be treated as active product and operating requirements. The v2.0 plan is strongest when it acknowledges where the business can fail and designs controls before volume hides the problem."),
table(
  ["Risk", "Severity", "Mitigation"],
  [
    ["Shipper payment default", "Critical", "Use Rupifi credit or NACH mandate; cap exposure; block dispatch without payment readiness; track failure rate weekly."],
    ["Carrier no-show or poor service", "High", "Verify carriers, start with known lane specialists, maintain backup pool, score reliability, penalize repeated failure."],
    ["Disintermediation", "High", "Own ERP workflow, payment rails, POD, dispute process, analytics, and service relationship so off-platform leakage is less attractive."],
    ["Low shipper adoption", "High", "Narrow ICP, assisted onboarding, repeat load templates, WhatsApp support, clear savings and reliability reporting."],
    ["Partner credit rejection rates", "High", "Maintain Track B NACH fallback; collect better underwriting data; avoid relying on one approval path."],
    ["Ops cost too high", "Medium", "Instrument manual steps, automate repeated patterns, keep lane scope narrow until playbooks stabilize."],
    ["Regulatory or compliance gaps", "Medium", "Avoid own lending, maintain audit trail, protect KYC/bank data, consult counsel for payment and mandate flows."],
    ["AI overclaiming", "Medium", "Keep AI assistive until data density and measured outcomes justify customer-facing decisions."],
    ["Competitive response", "Medium", "Build SME workflow lock-in and corridor density faster than incumbents copy surface features."],
    ["PTL distraction", "Medium", "Keep consolidation out of Phase 1–2 unless data proves corridor density and unit economics."],
  ],
  [2550, 1250, 5560],
  C.red
),
h2("Risk Review Cadence"),
bullet("Weekly during pilot: payment failures, disputes, carrier no-shows, delayed POD, manual override count."),
bullet("Monthly during Phase 1: repeat load ratio, lane density, ops cost per load, credit approval rate, NACH debit success."),
bullet("Before every expansion decision: confirm the new lane or city has enough demand, supply, and payment readiness to avoid false liquidity."),
callout("RISK PRINCIPLE", "The marketplace should scale only after the riskiest state transitions are boring: payment ready, carrier assigned, POD accepted, debit successful, carrier settled.", C.lightR, C.red),
PB(),

// ── 12. OPERATIONAL METRICS FRAMEWORK ─────────────────────────────────────────
banner("12", "Operational Metrics Framework", "Metrics that prove product-market fit, liquidity, and payment safety."),
h1("12. Operational Metrics Framework"),
body("The operational metrics framework must measure whether NaviG8r is replacing broker behavior with a more reliable system. Vanity metrics such as total carrier signups or app downloads are secondary. The primary proof is repeat shipment volume, clean collections, low dispute friction, and improving operating leverage."),
h2("Marketplace Metrics"),
metricTable([
  ["Gross Transaction Value (GTV)", "Total freight value of loads executed through NaviG8r.", "Month-over-month growth with stable take rate."],
  ["Executed Loads", "Number of completed shipments with POD and invoice record.", "Growth by corridor, not just aggregate count."],
  ["Repeat Load Ratio", "Share of loads from shippers who have booked before.", "> 60% by month 6 for pilot cohort."],
  ["Lane Density", "Loads per origin-destination-vehicle combination.", "Improves enough to reduce matching time and rate volatility."],
  ["Take Rate", "Net commission divided by GTV.", "8–10% blended unless strategic account requires exception."],
]),
h2("Trust & Service Metrics"),
metricTable([
  ["On-Time Pickup", "Loads picked up within committed pickup window.", "> 90% after pilot stabilization."],
  ["On-Time Delivery", "Loads delivered within agreed SLA or communicated tolerance.", "> 88% after pilot stabilization."],
  ["Carrier No-Show Rate", "Confirmed carrier fails to appear without approved replacement.", "< 3%."],
  ["POD Turnaround Time", "Time from delivery to usable POD upload.", "Median under 12 hours; 90th percentile under 36 hours."],
  ["Dispute Rate", "Delivered loads entering formal dispute flow.", "< 5%; classify by reason."],
]),
h2("Payment Metrics"),
metricTable([
  ["Rupifi Approval Rate", "Eligible shippers approved for embedded credit.", "Track by cohort and rejection reason."],
  ["NACH Activation Rate", "Track B shippers with active mandate before dispatch.", "100% for Track B loads."],
  ["Debit Success Rate", "NACH debits successful on first attempt.", "> 97%."],
  ["Days Sales Outstanding", "Average days from delivery/POD to collected cash.", "Trend down as payment architecture matures."],
  ["Carrier Settlement Time", "Time from delivery/POD resolution to carrier payment.", "Predictable and visible; improve cohort by cohort."],
]),
h2("Product & Operating Leverage Metrics"),
metricTable([
  ["Manual Touches Per Load", "Ops actions needed to move load from booking to close.", "Declines as product automates repeated tasks."],
  ["Quote Acceptance Rate", "Confirmed quotes accepted by shippers.", "Indicates price trust and lane fit."],
  ["ERP-Originated Loads", "Loads created from Tally/Zoho or imported sales order flow.", "Core anti-leakage indicator after integration launch."],
  ["Admin Banner Resolution Time", "Time to clear risk banners by category.", "Shows control tower effectiveness."],
  ["Support Tickets Per Load", "Customer or carrier issues per executed load.", "Should decline with better workflows and carrier quality."],
]),
h2("Investor Reporting Pack"),
bullet("Monthly GTV, executed loads, take rate, gross margin, and contribution margin by lane."),
bullet("Repeat load ratio by shipper cohort and top-lane retention."),
bullet("Payment readiness mix: Rupifi, NACH, advance/manual exceptions, failures, and collections aging."),
bullet("Carrier reliability score distribution and top reasons for exclusion or downgrade."),
bullet("Dispute reason distribution and financial impact."),
bullet("Ops cost per load and manual touch count trend."),
bullet("ERP integration adoption and ERP-originated load share."),

// ── FOOTER ────────────────────────────────────────────────────────────────────
PB(),
h1("Footer"),
thinHr(),
para([
  brun("NaviG8r Product Requirements Document v2.0", C.navy),
  run("  |  "),
  irun("Confidential  |  Generated August 2026  |  Output: NaviG8r_PRD_v2.docx")
]),
body("This footer language is also applied to the Word document footer so each page carries the product name, version, confidentiality marker, and document date."),
];

const doc = new Document({
  creator: "NaviG8r",
  title: "NaviG8r Product Requirements Document v2.0",
  description: "Ground-truthed and revised PRD for NaviG8r.",
  numbering:{ config:[
    { reference:"bullets", levels:[
      { level:0, format:LevelFormat.BULLET, text:"•", alignment:AlignmentType.LEFT,
        style:{ paragraph:{ indent:{ left:720, hanging:360 } } } },
      { level:1, format:LevelFormat.BULLET, text:"◦", alignment:AlignmentType.LEFT,
        style:{ paragraph:{ indent:{ left:1080, hanging:360 } } } },
    ]},
    { reference:"numbers", levels:[
      { level:0, format:LevelFormat.DECIMAL, text:"%1.", alignment:AlignmentType.LEFT,
        style:{ paragraph:{ indent:{ left:720, hanging:360 } } } },
    ]},
  ]},
  styles:{ default:{ document:{ run:{ font:"Arial", size:22, color:C.slate } } } },
  sections:[{
    properties:{ page:{
      size:{ width:12240, height:15840 },
      margin:{ top:1080, right:1200, bottom:1080, left:1200 },
    }},
    footers:{
      default:new Footer({
        children:[
          new Paragraph({
            alignment:AlignmentType.CENTER,
            border:{ top:{ style:BorderStyle.SINGLE, size:1, color:C.border, space:1 } },
            spacing:{before:80,after:0},
            children:[
              new TextRun({ text:"NaviG8r PRD v2.0  |  Confidential  |  August 2026", font:"Arial", size:16, color:C.muted }),
            ],
          }),
        ],
      }),
    },
    children,
  }],
});

const artifactPath = "/opt/cursor/artifacts/NaviG8r_PRD_v2.docx";
const docsPath = "/workspace/docs/NaviG8r_PRD_v2.docx";

const writeDoc = async () => {
  const buffer = await Packer.toBuffer(doc);

  fs.mkdirSync(path.dirname(artifactPath), { recursive:true });
  fs.mkdirSync(path.dirname(docsPath), { recursive:true });
  fs.writeFileSync(artifactPath, buffer);
  fs.writeFileSync(docsPath, buffer);

  const artifactSize = fs.statSync(artifactPath).size;
  const docsSize = fs.statSync(docsPath).size;
  console.log(`${artifactPath} ${artifactSize} bytes`);
  console.log(`${docsPath} ${docsSize} bytes`);
};

writeDoc().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
