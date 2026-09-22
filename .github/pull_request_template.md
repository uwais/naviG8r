<!--
Full rules and the reviewer's checklist: docs/PR-STANDARD.md
Agents opening a PR here: read that file first. It is short.
-->

## What this changes

<!-- Two or three sentences a non-coder can follow. No function names unless you explain them in
the same breath. If you cannot describe it without jargon, the PR is probably too big. -->

## Why

<!-- The bug, the ticket, or the quoted feedback. If it came from a pilot user, quote them. -->

## What breaks if this is wrong

<!-- The honest worst case. "Nothing, it is a copy change" is a fine answer when it is true. -->

## Verified

<!-- Only things you actually ran. Label each claim:
     ran     - you executed it and saw the result
     read    - you read it in the source
     claimed - someone else said so and you did not confirm it                                 -->

| What | Command or method | Result | Label |
|---|---|---|---|
|  |  |  |  |

## Not verified

<!-- Required. "Nothing" is only acceptable if it is true. A skipped check is a failed check
     until it is named here. -->

## How to check this without reading code

<!-- Concrete steps on beta or the emulator, so someone who does not read Dart or TypeScript can
     confirm it works. If there is genuinely no such path, write "no non-code check exists" and
     say who needs to read the diff. -->

---

- [ ] One problem per PR. If this supersedes an earlier PR, say which, and close it.
- [ ] No exploit detail in the description — this repository is public. See `docs/PR-STANDARD.md`.
- [ ] **Changes a screen?** Every user-visible element you added is named in a test. Ask: if
      someone deleted it tomorrow, what turns red? If the answer is nothing, it is not protected.
