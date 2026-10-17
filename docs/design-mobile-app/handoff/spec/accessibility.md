# Accessibility spec

Applies to every screen. Each "announced" line becomes a `SemanticsService.announce` (or a live-region widget) and a named test assertion where practical.

## Accessibility notes

WCAG 2.2 AA. Applies to every screen on this canvas. Contrast values are the design system's.

### Rules for every screen

| Topic | Rule |
|---|---|
| Contrast | Body ink on page 14.0:1; captions slate 5.0:1; status words 5.6 to 12.9:1 on their tints; control borders control-border 3.6:1; focus ring navy 14.6:1. Gold never carries text on light grounds. |
| Not colour alone | Every status has a word. Step states also differ by marker: tick (done), number with halo (yours), clock (waiting), "!" (problem). Map pins are named in the chip. |
| Targets | 48 x 48 dp minimum, 56 dp for driver primaries. Quiet text buttons keep 48 dp height. At least 8 dp between adjacent targets. |
| Text size | Works at 200% system font: cards grow, nothing truncates except the header (full name is in its accessible label). Fact rows wrap to stacked label over value. The sticky action bar stays; content scrolls above it. |
| Width | All screens built at 360 dp; no horizontal scroll. Web tables scroll inside their own box. |
| Icon buttons | None in the app: every action has a word. Decorative icons are aria-hidden. Copy buttons are labelled with what they copy: "Copy truck number KA01AB1234". |
| Motion | Spinners respect reduce-motion (show the word only). Sheets fade, no slide, when reduce-motion is on. |
| Dark mode | Off. The app does not follow the phone's dark setting. |

### Heading and focus order

| Screen | Headings | Focus order |
|---|---|---|
| Tab screens | H1 screen title; H2 per section (Needs you, Your shipments, Today) | Header account button, Back if any, content top to bottom, action bar, bottom tabs |
| Shipment, booking | H1 route or shipper; the step list is one ordered list named "Steps for this shipment"; the open step's question is H2 | Header, Messages, Change or cancel, each step in order, inside the open step: copy rows, then primary, then secondary |
| E-way bill form | H1 "Enter the bill's details" | Fields in the bill's order, then Save. On a failed save, focus moves to the error summary, which links to each field. |
| Bottom sheets | Sheet title is the dialog's name (aria-labelledby) | Focus moves to the title, then choices, primary, Cancel. Focus is trapped while open; Back or Cancel closes it and returns focus to the button that opened it. |
| Driver e-way bills | H1 "E-way bills"; each bill is a region named "E-way bill for [shipper]" | Back, then bills in drop order, then Call |

### What a screen reader announces

| After | Announced (polite unless marked) |
|---|---|
| Send code | "Code sent to +91 98450 12345." |
| Wrong code | Assertive: "That code is not right. Check the SMS and type it again, or send a new code." |
| Match my route | "2 lanes with room for 80 kg, closest to your route first." or the empty message |
| Get price | "Price for 80 kg: 2,640 rupees. This is the full price." |
| Change weight, pickup or drop | "Price cleared. Get a new price before paying." |
| Too heavy | Assertive: "This lane does not have room for that weight. Enter a lower weight, or choose another lane." |
| Pay and book returns | "Booked. Waiting for Ravi Roadways to accept." Focus moves to the shipment's H1. |
| E-way bill answer | "Saved: this load needs an e-way bill." |
| Copy | "Truck number copied." or assertive "Could not copy. Press and hold the number to copy it." |
| Save e-way bill | "E-way bill saved. Nothing more for you to do until delivery." Errors: assertive summary, then each field's error when focused. |
| Accept with truck | "Accepted with KA01AB1234. Sharma Textiles can make the e-way bill now." |
| Assign driver | "Prakash Naidu assigned. You can start the trip on loading day." |
| Start trip | "Trip started. Shippers are told their goods are on the way." |
| Confirm delivery | "Delivery confirmed at Guindy. Next stop: Ambattur." |
| Any list loading | "Loading [lanes \| shipments \| bookings \| trips]." once, then the count when loaded |

### Role checks to test

- Signed in as a driver, search every screen's accessibility tree for "₹", "paid", "commission", "receive", "payout", "net". None may appear.
- Signed in as a dispatcher, the payment block and bank details never render, and the status reads "Delivery confirmed".
- Signed out, no tabs render; only the start screen and sign-in.
