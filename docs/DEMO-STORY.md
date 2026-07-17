# The story to open with

Use this as a spoken intro before Act 1, then thread the two short callbacks in where marked.
It's grounded in what actually happened on December 10, 2021, not an invented scenario.

---

## The Friday night we didn't have to have

"On a Friday evening in December 2021, a two-line proof-of-concept went public for a
vulnerability in a logging library. Not an obscure one. Log4j. It was sitting inside almost
every Java application on the planet, often several layers deep, often nobody on the team could
even tell you it was there.

By that weekend, security teams everywhere were running the same command: grep every repo they
owned for `log4j-core`. Then messaging every team that came back a hit. Then waiting. Because for
most of those teams, the only way to fix it was: pull the on-call engineer off whatever they were
doing, edit a version number, rebuild, run the test suite, redeploy, and hope nothing else broke
on the way. Multiply that by every service, every team, every weekend on-call rotation, for
weeks. Some organizations were still finding stragglers a month later, an old fat WAR nobody
remembered was still running the vulnerable version, because nothing about the process made that
visible.

That's not a hypothetical. That's what actually happened, broadly, industry-wide, that December.

Here's the question worth sitting with: what if the same fire drill played out differently?"

---

**→ Transition into Act 1.** Build, deploy, show it's vulnerable, exactly as it happened that
Friday. Then, at Beat 6 (the module swap), come back to the story:

> "This is the moment that Friday night didn't have. One person. One command. The fix lands in
> the shared module, the WAR never moves, and the checksum proves it. No one had to touch the
> application. No war room, no all-hands page, no 2am rebuild."

**→ At Beat 9 (the PR)**, close the loop on the part that story genuinely got wrong at most
orgs, not because people didn't care, but because there was no non-blocking way to do it:

> "And the paperwork still happens, just not on the critical path. That's the part most teams
> didn't have the luxury of separating that weekend, fixing production and updating source
> control were the same terrifying, blocking step. Here they're not."

---

**→ Transition into Act 2**, if you're running both acts:

> "Same story, different infrastructure. If that Friday night's services were running in
> containers instead of on VMs, here's what the equivalent fire drill looks like."

**→ At the Canary beat**, land the point this way:

> "Nobody had to trust the fix on day one, industry-wide, in December 2021, either. One pod
> takes the patched image first. The rest of the fleet watches its health before following. If
> this were that Friday, you'd know within minutes whether the fix was safe, not days."

**→ At Rollback**, close with the honest caveat that keeps the whole story credible:

> "None of this claims to catch everything, we've been explicit already that a structural diff
> can't see every behavioral change. That's exactly why this exists: not because the fix is
> guaranteed perfect, but because when it isn't, the fleet reverts in one step instead of another
> weekend of manual redeploys."

---

## Why tell it this way

The story isn't decoration, it's doing real work: it gives the audience a *before* to compare the
demo's *after* against, using an incident most technical people in a banking/FSI audience will
recognize immediately, without needing it explained. And because every beat in the demo runs
real tools against real artifacts, the callbacks aren't asking anyone to imagine a better
world, they're watching one.
