# Components

Build these once in `apps/driver_pilot/lib/ui/` (one file each) and use them everywhere. Mockups: `mockups/cp-*.html`. Every component supports the states listed; each state gets a widget test with a named assertion (see `PROMPTS.md`, testing rules).

| Component | Flutter shape | States | Rules |
|---|---|---|---|
| `NvHeader` | `PreferredSizeWidget` for `AppBar` | default, pressed, focus, long name (ellipsis), with Back, driver task title | One `InkWell` button: company (Poppins 15/600) + "Person · Role" (caption) + chevron. Semantics label = full company, person, role + "Switch company or sign out". Opens `NvAccountSheet` |
| `NvAccountSheet` | modal bottom sheet | default, switching (loading), error | Name, full phone, companies as radio rows, Add a company, Sign out, Close |
| `NvButton` | wraps Filled/Outlined/Text button | primary, secondary, destructive, quiet × default, pressed, focus, disabled + reason, loading, success | Min 48 dp (56 for driver primaries). Loading keeps the label and adds a 18 dp progress ring. Disabled always has a reason line under it. Buttons never turn red on error |
| `NvStatusLabel` | `Container` + `Text` | attention, info, good, problem, ended | Word required. Radius 8. Not tappable. Words in `copy.md` |
| `NvStepList` | `Column` of `NvStep` | done, now (yours), wait (someone else), later, problem, loading list, saving, success, error | Marker 32 dp: tick / number with 4 dp halo / clock / "!". Connector 2 dp, navy when done. Only `now` and `problem` open a panel with a button; `wait` opens a grey panel without one. On phones the panel spans full width under the step title. Each step's Semantics: "Done:", "Your step:", "In progress:", "Step n of m, later:" |
| `NvCopyRow` | `Row` | default, pressed, focus, copied (3 s), loading, empty (no value + guidance), disabled (not available yet), error (clipboard blocked) | Label, value in mono, "Portal field: …" line, Copy button. Copies the value without spaces. Announces "[label] copied" |
| `NvField` | `TextFormField` + label above | default with help, focus, filled, optional, error, disabled + reason, read-only, loading, success | Label always visible above (not floating). Help below; error replaces help. Fixed-option inputs use `NvChoiceChips` or radio rows instead |
| `NvChoiceChips` / `NvChoiceRows` | `Wrap` of chips / radio list | none selected, selected, focus, disabled | Never preselect a choice the user has not made |
| `NvListCard` | `InkWell` card | default, pressed, focus, needs-you (navy border), unavailable (Full), loading skeleton, empty, error | The whole card is the only tap target. No buttons inside. Route line, caption, facts row (label over value), status label, optional "Next:" line |
| `NvSheet` | `showModalBottomSheet` wrapper | nothing chosen, chosen + focus, loading, error (stays open, choice kept), success (closes + announce), empty | Title is a question. Primary and Cancel full width, equal size. Focus moves in and returns to the opener |
| `NvMap` | existing Google map, 112 to 148 dp tall | default, loading, location off, failed | Never the only way to set a place: text fields come first. Chip "Pickup and drop" names the pins |
| `NvMessage` | inline banner | info, attention, good, problem | Used for "saved" and errors near the thing that failed. Live region |
| `NvActionBar` | bottom `SafeArea` container | — | Holds the screen's primary action above the tabs so it is visible at 360 x 800 |

## Format helpers (one file, unit tested)

`formatDate(18 Oct)`, `formatDateRange(18 – 19 Oct)`, `formatTimeIst(16:40 IST)`, `formatRupees(₹2,640, Indian grouping, no paise unless non-zero)`, `formatKg(80 kg)`, `formatBillNumber(3412 0098 7654)`, `shipmentName(route + date)`. Replace every existing ad-hoc date, money and ID formatting with these.
