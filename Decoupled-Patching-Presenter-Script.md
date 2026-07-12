# Decoupled Patching — Presenter Script
### Talking track for "Decoupled Patching" (Project Mythos), 21 slides

**How to use this:** this isn't meant to be read word-for-word — it's a talk track. Say it in your own voice, and skip lines that don't fit your audience's technical depth. Rough timing is noted per slide; total run time is **~38–46 minutes** at a conversational pace, plus Q&A. Each section ends with a one-line transition so the deck flows instead of feeling like 21 separate topics.

---

## Slide 1 — Title: "Decoupled Patching"
**~30 sec**

> "Today I want to walk you through something that sounds narrow — how we patch a security bug in a library — but actually changes how fast your teams can move. The short version: separating the code your developers write from the third-party libraries they borrow, so a security patch stops being a reason to stop shipping features."

**Transition:** "Let me start with the problem this actually solves, because it's one every one of you has lived through."

---

## Slide 2 — "A one-line fix shouldn't cost a full rebuild"
**~2.5 min**

> "December 2021. Log4Shell. If you were anywhere near a Java shop that month, you remember it. A critical flaw was found in Log4j — one of the most widely used logging libraries on the planet. Overnight, a huge share of the world's Java applications were suddenly known to be exploitable.
>
> Here's the maddening part: for most teams, *their own code was completely fine.* Nobody had a bug. The only thing wrong was a version number, buried in a dependency file. The actual fix was one line — bump `2.14` to `2.17`.
>
> But because of how applications are traditionally packaged, that one-line change forced teams through the entire pipeline: edit the version, commit, kick off the full build, compile code that didn't change, run every test — for a fix that had nothing to do with their code. That's the fire-drill. And it's not a one-time story — AI is making it dramatically cheaper to *find* vulnerabilities in open source, so these fire-drills are only going to come faster and more often."

**Transition:** "So the real question is: why does a library patch have to touch your code at all? To answer that, we need to look at what's actually inside an application."

---

## Slide 3 — "Every application is really three layers"
**~2.5 min**

> "Every app you run — no matter the language — is really three layers stacked on top of each other. Layer one is *your code*, the business logic your team actually writes. Layer two is *third-party libraries* — Spring Boot, Express, FastAPI, loggers, parsers, the stuff you borrowed. Layer three is the *runtime* — the JVM, Node engine, or Python interpreter that actually executes everything.
>
> Traditionally, layers one and two get welded together into a single sealed package. That's the root of the problem — but let me be precise about *why* libraries change, because it's not one reason. Libraries change for two genuinely different reasons: planned upgrades — new features, an architectural shift, a framework version bump — that you choose and schedule yourself, on your own cadence, much like your own code. And security fixes, which the world hands you on a clock nobody controls. This deck, and everything Lightwell does, is about that second kind — the flaw you didn't choose and can't plan around. The planned-upgrade path stays exactly what it is today: a deliberate, tested, forward version bump on your own schedule.
>
> One thing I want to be precise about, because it's a fair question people ask: does this mean we're hand-managing a `lib` folder ourselves, fighting Spring's whole transitive dependency tree by hand? No. **Your build tool still does that work, completely unchanged.** Maven, Gradle, npm, pip — they still resolve the entire dependency graph, every transitive dependency, every version conflict, exactly as they do today. Decoupling doesn't touch *how* dependencies get resolved. It only changes *where the build's output lands* afterward. Spring Boot's own Layered JARs feature already does exactly this — dependencies, snapshot dependencies, and your classes each land in their own layer, computed straight from Maven's fully resolved graph."

**Transition:** "So what happens when we stop gluing them together? That's where it gets interesting — and where some very old, slightly odd terminology comes in."

---

## Slide 4 — "Three ways to package: Fat, Thin, Hollow"
**~3.5 min**

> "There are three ways to draw this line, and they have memorable — if slightly silly — names.
>
> **Fat** is the traditional approach: your code and every library it needs, sealed into one file. Think of a welded appliance — if one internal wire is bad, you don't fix the wire, you recall the whole appliance.
>
> **Thin** flips that: the package contains *only your code*. The libraries are resolved by your build and packaged in their own layer — I'll be specific in a minute about exactly where that layer lives, because it depends on your deployment target. Think of a desktop computer: the tower does your specific work, but the mouse plugs in externally. Mouse breaks, you swap the mouse, the tower's untouched.
>
> **Hollow** is the mirror image: it's *just* the runtime and the libraries — the shell — with zero application code. Your code is the payload dropped in. Think of a game console: firmware updates roll out, your game cartridge is untouched.
>
> Now — I want to be upfront about something, because I'd rather say it than have someone in the room thinking it. Almost everyone here is running Fat JARs today. That's not a knock on anyone's engineering — it's the build default. `mvn package` gives you a Fat JAR out of the box; every tutorial teaches you to bundle everything. The rebuild cost stays completely invisible... until a Log4Shell moment forces the issue.
>
> Here's the important part, though: **Fat and Thin/Hollow aren't a gate you have to pass through — they're a sequence.** Lightwell's trusted, backported patches and the verification chain I'll walk you through already help a Fat JAR *today*, exactly as it's packaged right now. Decoupling to Thin or Hollow is what makes the rebuild itself fast — it's the next step, not a prerequisite for the first one."

**Transition:** "That's the concept. Now — and this is a question we get from almost every technical audience — how does this actually work once you're running in containers?"

---

## Slide 5 — "Thin & Hollow: containers vs. VMs"
**~3.5 min**

> "This is the slide I want to get exactly right, because it's easy to overstate. Let me lead with the correction up front: **most Lightwell fixes land in your application's own dependency layer — not the shared OS base image.** That distinction matters, so let's walk through it.
>
> In containers, your build tool still resolves everything — Maven, Gradle, npm, pip compute the full transitive graph, exactly as today. What's different is that the resolved dependencies typically end up in their own layer within *your app's own image* — separate from your code, but still part of your app, not some shared image used by every other application in the cluster. When Lightwell ships a fix, your app's own dependency layer rebuilds — and because your code layer and the OS layer underneath are both cached, that rebuild is fast, seconds not minutes — then a rolling redeploy.
>
> The shared OS base image — UBI, Hardened Images — is a *separate* thing entirely. OS-level packages like glibc or openssl are patched through the traditional RHEL and UBI errata process, which is outside Lightwell's typical scope. I don't want to conflate the two.
>
> One more thing worth being direct about: the instinct some platform teams have is 'let's put shared libraries on a network mount every container reads from.' Don't do that — it breaks image immutability, since two containers from the same image should behave identically, and it breaks your SBOM and signing story, because scanners describe the image, not what's mounted at runtime.
>
> On VMs and app servers, the older model still applies — swap the library in `/lib`, restart the app, no image to rebuild at all. That's operationally simpler, which is exactly why it was the standard for years — but containers are the default going forward, for the immutability and provenance guarantees.
>
> One more question I've gotten directly, and it's a good one: what about legacy EAR/WAR deployments, where the app server extracts the libs directory at deploy time? Short answer — we're not proposing to hot-swap jars inside a deployed archive's exploded directory. If dependencies are already externalized into an app-server-level shared module — WildFly's `modules/` directory, WebLogic or WebSphere shared library deployments — Lightwell's fix lands once in that shared module, and every WAR referencing it picks it up on restart. If a WAR still bundles its own libraries internally, that application still needs a rebuild to pick up the fix, same as today. Externalizing to a shared module is a one-time investment, independent of whether Lightwell exists."

**Transition:** "With that precisely grounded, let's look at what the day-to-day patching flow actually looks like."

---

## Slide 6 — "Patching without re-releasing your app"
**~2 min**

> "Here's the flow end to end. A CVE gets published. Lightwell — more on that shortly — ships a tested, signed backport of your pinned version. Your pipeline pulls it and redeploys automatically. It's staged and verified before it goes fully live.
>
> The headline: no version chase, no fire-drill, and your *application code* is unchanged — you're not shipping new features. One precise point, because a sharp reviewer will raise it: the patched library is *not* the same binary. It's a distinct, uniquely-versioned artifact — signed, SBOM'd, and tracked — which is exactly what makes it auditable and lets you roll back. (If asked for specifics on the exact naming format: don't commit to one — say only that backports carry a distinguishing, trackable qualifier, and that the precise format is still being confirmed with the Lightwell team.) And to be clear, this isn't 'nothing gets tested' — the patch *is* verified before it ships; we'll walk through exactly how in a few slides, because that's usually the first question in the room."

**Transition:** "Quick note before we go further — this isn't a Java-only idea."

---

## Slide 7 — "The same idea in Java, Node.js, and Python"
**~1.5 min**

> "The Fat/Thin/Hollow language comes from the Java world, but the concept translates directly. In Node.js, it means treating `node_modules` as an externalized, pre-hardened layer instead of bundling it with your source. In Python, it's isolating your app scripts from the virtual environment that runs them, with certified wheels refreshed centrally. Different ecosystems, same rule: your code in one place, your libraries in another."

**Transition:** "So who actually runs these two different kinds of change day to day? That's where the two-pipeline model comes in."

---

## Slide 8 — "Two pipelines, one trusted build"
**~2 min**

> "Once code and libraries are separated, you can separate *who owns the change* and *what triggers it* — while it's still one build pipeline underneath. Pipeline A is the AppDev track: owned by developers, triggered only when someone commits a real feature or bug fix. It compiles and tests your proprietary code and is completely immune to CVE fire-drills.
>
> Pipeline B is the Platform and Patching track: owned by automation, triggered when Lightwell publishes a fix at your pinned version. And I want to be precise here, because a sharp platform engineer will push on it — Pipeline B does *not* magically skip the build or bypass your repo. What it does is open a version-bump PR for you, with a tool like Renovate or Dependabot, so the change is committed to source control for reproducibility and audit — then it runs the *same* build, canary-verifies it, and rolls it out. Same build, same repo. The only difference is the trigger and the owner.
>
> So the value isn't 'you avoid rebuilding the image' — you don't, and you wouldn't want to. The value is that a CVE never pulls a developer off their sprint: the patch flows through the same trusted, automated pipeline without a human in the loop. That's exactly the kind of pipeline automation Red Hat Services helps teams stand up — TSSC, Tekton, developer self-service."

**Transition:** "Before we talk about how the fix gets to you, let's back up one step — how do you even know what needs patching in the first place?"

---

## Slide 9 — "Finding the CVEs: software composition analysis"
**~2 min**

> "This is the detection layer — Software Composition Analysis, or SCA. These tools scan your dependency tree and match it against vulnerability databases like OSV and the NVD. On the free side you've got things like GitHub Dependabot, OSV-Scanner, and Trivy. On the commercial side, Snyk, Mend, Endor Labs, and others — some of the newer ones add reachability analysis, meaning they check whether a vulnerable code path is actually callable in your app, which cuts a lot of noise.
>
> On the Red Hat side, we have Dependency Analytics — it's not just an IDE plugin, by the way, it also runs in Jenkins and Tekton — paired with Trusted Profile Analyzer for SBOM and VEX data.
>
> One thing worth being precise about: none of these tools discover *new*, unknown exploits. They detect *known*, published CVEs. What they do is find and rank what's already out there — and then point you toward the fix."

**Transition:** "And that raises the next question — if a scan comes back with two hundred CVEs, where do you even start?"

---

## Slide 10 — "Which to fix first: risk-based prioritization"
**~2.5 min**

> "CVSS severity alone is a weak way to prioritize — it's a technical severity score, but it says nothing about whether *you're* actually exposed. So you layer real context on top: is the system internet-facing? Is it business-critical or handling regulated data? And — the sharpest layer — is it actually exploitable in *your* codebase?
>
> That last one is where I'd point you to something Red Hat now offers natively: **Exploit Intelligence** in Trusted Profile Analyzer. Most tools stop at EPSS — a machine-learning *prediction* of exploit probability that never looks at your actual code. Exploit Intelligence goes further: it scans your codebase directly to confirm whether you're actually reachable by a given exploit. That's a meaningfully stronger signal than a generic probability score.
>
> I'll mention — one large bank we've talked to does something similar: they start from the CVE score and add weight for public-facing exposure, business criticality, and regulated data. It's the same instinct, formalized."

**Transition:** "Okay — you know what's vulnerable, and you know what to fix first. That actually sets up a question I know some of you are already thinking about."

---

## Slide 11 — "Beyond the CVE count: what actually matters"
**~2.5 min**

> "Let's address something directly, because I'd rather bring it up than have it sit in the room unspoken. If you've looked at hardened-image vendors like Chainguard, you've seen the argument: scan their image versus a traditional one, and they show near-zero CVEs against hundreds. That's true, as far as raw counts go.
>
> But a raw count is the wrong scoreboard. A scanner counts every package *present* in an image, whether or not it's ever actually called by your code, and whether or not that CVE even applies in your context. Fewer packages naturally means a smaller number — that's real, but it's not the same as *safer*.
>
> The question that actually matters isn't 'how many CVEs exist' — it's 'which ones can actually reach and hurt my running application?' That's exactly what Exploit Intelligence, which I just mentioned, answers: it scans your codebase directly to confirm reachability, not a package inventory.
>
> And here's a number worth sitting with: across Red Hat's own products, of 1,656 CVEs analyzed, only 7 — that's 0.4 percent — were ever confirmed exploited in the wild. Most CVEs are never the real risk. Knowing which handful are is the whole game. Fewer packages reduces noise. Knowing what's reachable removes it."

**Transition:** "Since Chainguard's in the room now, let's look at where they're actually headed — because it's worth knowing the trajectory, not just today's pitch."

---

## Slide 12 — "Chainguard: where they're expanding"
**~2.5 min**

> "Chainguard isn't standing still, and it's worth knowing their direction of travel. They're pushing on five fronts at once: their Libraries offering — Java and JavaScript remediation — is now GA, which puts them in direct overlap with what Lightwell does. They're embedding in AI coding assistants, so their images become the path of least resistance the moment code gets generated — and I'll be straight with you, that's a real gap for us today, we don't have an equivalent integration yet. They've launched hardened CI/CD actions. They're adding RPM support and FIPS enhancements specifically aimed at lowering the cost of switching off RHEL. And they've integrated with third-party security dashboards like Wiz, so their low-CVE story shows up right where security teams already look.
>
> The pattern matters more than any single feature: they're expanding on every axis — image, library, pipeline, IDE, dashboard. Our answer isn't to match them feature for feature. It's a different value axis entirely — backport-to-pinned-version, exploit intelligence that actually scans your code, and a trusted factory that operates at enterprise scale. We'll get to all three."

**Transition:** "With prioritization and that framing in hand, let's talk about where the actual fix comes from."

---

## Slide 13 — "Project Lightwell: trusted patches at the source"
**~3 min**

> "This is Project Lightwell — a joint IBM and Red Hat initiative, roughly twenty thousand engineers plus AI, acting as a clearinghouse for open source security. The pipeline is: scan, backport, test, sign, deliver. You integrate with a one-line config change pointing your build tools — Artifactory, Nexus, Maven — at Red Hat's secure registry.
>
> I want to be precise about the AI piece, because it's easy to overstate. This is *not* 'AI writes the patch and ships it.' Red Hat's own framing is: **AI accelerates, humans decide.** AI handles the high-volume work — initial data ingestion, triage, prioritization. The critical judgment calls — is this backport actually compatible, how do we develop the patch safely, when do we disclose upstream — those stay with human engineers. That's a *stronger* safety story than a fully automated pipeline, not a weaker one.
>
> The key detail on delivery: you get the fix backported to the *exact version you already run* — not a forward upgrade with new features bundled in. Every package ships SLSA Level 3 build attestation, HSM-backed signing, and a full SBOM."

**Transition:** "That naturally raises a boundary question worth answering directly before we move on."

---

## Slide 14 — "Where Lightwell's responsibility ends"
**~2 min**

> "A fair question, and one worth answering head-on: Lightwell secures the libraries you borrow. What covers the code you actually wrote?
>
> To be precise about the boundary — Lightwell covers third-party open source libraries and dependencies across Java, Node, and Python: scanned, backported, tested, signed, delivered. What's still yours is your own business logic — input validation, custom logic bugs, secrets management, testing of the code your team actually wrote.
>
> That gap in between isn't ignored, either. The SCA tools I mentioned earlier already cover detection on your own code path too, and we're actively engaging ecosystem partners to close that last mile — rather than leaving customers to figure it out alone. Being precise about where the boundary sits is what makes this story hold together instead of raising more questions than it answers."

**Transition:** "Which brings us to the question every technical buyer asks at this point, and it's a good one."

---

## Slide 15 — "How do we know the patch won't break your app?"
**~3 min**

> "Decoupling doesn't skip verification — it splits it into two halves: trusted at the source, and verified in your environment. We just covered the source half. Here's what happens in your environment, five layers deep.
>
> One — the change is *engineered to be tiny.* Only the fix, at your exact version, nothing else. Two — an *automated compatibility gate* — an API and ABI diff, tools like japicmp or revapi in the Java world — flags any change to the public surface before anything ships. Three — an *expanded test suite*, smoke and contract tests that exercise the integration points actually touching the patched library. Four — *staged rollout with health checks*: canary to one instance first, and error rate, latency, and health decide promotion. Five — *instant rollback*, which is trivial because it's the same one-step swap as the patch itself.
>
> Each layer catches what the one before it might miss."

**Transition:** "That's how it works for one app. Now — a fair challenge we got on this deck: what happens when it's not one app, it's hundreds?"

---

## Slide 16 — "At scale: the trusted software factory"
**~2.5 min**

> "Picture a real customer: hundreds of applications, and Lightwell surfacing thousands of patch recommendations across them. Nobody's running those five verification steps by hand, repo by repo — that falls apart past a handful of services. And it's not just rebuilds, either — coordinating restart windows across a large fleet is its own operational burden that platform teams feel every single patch cycle.
>
> This is where Red Hat's **trusted software factory** comes in, built on **Konflux** — an open-source, Kubernetes-native CI/CD platform. It runs that entire five-layer chain as automated, policy-gated pipelines across your whole fleet. Every build is SLSA Level 3, signed, SBOM'd, and Policy-as-Code decides fast-lane versus hold-for-review at the *platform* level — not something each team configures on their own. And the rolling, staged rollout model replaces one big synchronized outage window with continuous, low-impact updates.
>
> Simple way to think about the split: Lightwell supplies the trusted patch. The trusted software factory is what actually applies it, automatically, at scale."

**Transition:** "Let me make that concrete with a walk-through, because 'trusted software factory' can sound abstract until you see it against a real CVE."

---

## Slide 17 — "From CVE to fixed: a day at a bank"
**~3 min**

> "Let's ground all of this in a scenario. Picture a bank running thousands of services, and a CVE just published. Here's what actually happens, step by step — and I want to be upfront that this is the same approach from the rest of this deck, not a new idea. Nothing here requires an AI agent; where AI does help — detection and risk scoring — it stays exactly as scoped as I described a few slides back.
>
> Step one: Lightwell backports, tests, and signs the fix — same day, not weeks later. Step two: your SCA tooling plus Exploit Intelligence confirm the vulnerable path is actually reachable in your code, and a risk score gets set. Step three: the automated compatibility gate and expanded test suite run — no human needed yet. Step four: risk-based routing — low risk takes the fast lane, elevated risk goes to your own full regression suite. And this is the part I want to make sure lands clearly — step five and six are the two pieces that are easy to skip over but matter most: a **canary rollout**, one instance first with health checks gating promotion, before it ever goes fleet-wide through the trusted factory — and a **rollback safety net**, where any regression automatically reverts to the last known-good version, before your customers ever notice.
>
> Your team stays in the loop at exactly two points: elevated-risk patches get your own security sign-off, not just an automated gate, and every deployed fix carries a full SBOM and signed provenance for your audit trail. Canary and rollback aren't optional extras bolted on for this walkthrough — they're built into the trusted software factory from day one."

**Transition:** "Now — I don't want to oversell any of this. Not every patch should move at the same speed, and that's deliberate."

---

## Slide 18 — "Not every patch takes the fast lane"
**~3 min**

> "Even a minimal, well-behaved backport can shift *behavior*, not just structure. A security fix that lived in caching logic can cause a performance regression. Fixing an off-by-one error can break code that was quietly written to compensate for that exact bug — now it over-corrects the other way. A compatibility diff won't catch either of those, because it checks structure, not behavior.
>
> So Red Hat flags each backport with a behavioral-change risk indicator. Low risk — self-contained, low behavioral impact — takes the fast lane: rebuild, smoke test, canary, done. Elevated risk — anything touching performance or logic your code might lean on — gets routed to a full regression suite before release.
>
> And I want to say this plainly, because it's the honest answer to a skepticism I know some of you have: **no customer has to trust the fast lane on day one.** You can keep full regression testing on everything, and you'll still get the win of never manually chasing versions or hand-backporting fixes yourself. The fast lane is something you grow into as the track record earns it — it's not a requirement to get value from this."

**Transition:** "Which leads to the most important slide in this deck — the one where we tell you where this approach actually has limits."

---

## Slide 19 — "The honest limit — and the backstop"
**~2.5 min**

> "I'd rather tell you this myself than have you find it the hard way. Even a fix with *zero new features* can shift behavior — a performance regression, a logic shift where compensating code now over-corrects, changed timing or ordering. Zero new features, and behavior still moves. That's exactly what regression testing exists to catch, and it's why we don't pretend a compatibility diff is the whole answer.
>
> The backstop is three things: Red Hat flags each fix's behavioral-change risk so you know when to slow down; canary plus observability catch a regression in one instance before it ever reaches the fleet; and instant rollback plus full SBOM provenance mean critical dependencies always get full QA, no exceptions.
>
> We're telling you it isn't a hundred percent — and that honesty is exactly why the backstop exists."

**Transition:** "So — pulling all of this together, here's what it actually buys you."

---

## Slide 20 — "Why it matters"
**~2 min**

> "Three things. No more fire-drills — security patches land on the platform, not in the middle of someone's sprint. Builds in kilobytes — artifacts drop from hundreds of megabytes to kilobytes, so pushes go from minutes to seconds. And audit-ready by default — every library is signed, tested, and traceable, so compliance stops being a fire-drill of its own.
>
> One thing worth restating because it matters for the room: this starts paying off on day one, on the Fat JARs you're already running — you don't have to win an internal repackaging effort before you see value. It compounds further as you adopt Thin and Hollow. All of it's powered by Project Lightwell — scanned, backported, tested, and signed packages at your pinned version, through a one-line registry change."

**Transition:** "That's the whole story. Let me leave you with where to go next."

---

## Slide 21 — "Thank you"
**~30 sec**

> "With Lightwell supplying verified fixes and decoupled packaging making them trivial to adopt, every CVE becomes a routine, automated, low-risk update instead of a fire-drill. Happy to take questions, or go deeper on any slide — the verification chain and the bank walkthrough are usually where the room wants to spend the most time."

---

## Anticipated questions (quick-reference)

| If they ask... | Point back to |
|---|---|
| "Isn't this hard with transitive dependencies (Spring, etc.)?" | Slide 3 — the build tool (Maven/Gradle/npm/pip) still resolves everything; decoupling only changes where output lands. |
| "Everyone I know runs Fat JARs — does any of this even apply to us?" | Slide 4 — Fat and Thin/Hollow are a sequence, not a gate; Lightwell + verification help a Fat JAR today. |
| "Do Lightwell fixes patch the base image?" | Slide 5 — no, most land in your app's own dependency layer; base image is a separate, traditional errata path. |
| "What about legacy EAR/WAR on app servers?" | Slide 5 — shared-module externalization (WildFly/WebLogic/WebSphere) patches once; a still-bundled WAR needs a rebuild, same as today. |
| "Will customers actually trust a lower-layer fix?" | Slide 18 — full regression stays available; fast lane is earned, not required. |
| "What if the fix changes behavior, not just the API?" | Slide 19 — the honest limit; canary + rollback + SBOM is the backstop. |
| "How does this work with containers / Kubernetes?" | Slide 5 — application dependency layer vs. shared base image, never a mutable mount. |
| "How is this different from generic SCA tools?" | Slide 9 vs. 13 — SCA finds and ranks; Lightwell backports to your pinned version. |
| "Isn't this just 'AI patches everything'?" | Slide 13 — AI accelerates, humans decide the judgment calls. |
| "Two pipelines? In containers you still rebuild the whole image, right?" | Slide 8 — correct: same build, same repo. Pipeline B = an automated version-bump PR (Renovate/Dependabot), different trigger/owner, so no developer is pulled in. |
| "How does this scale past a handful of apps?" | Slide 16 — the trusted software factory / Konflux. |
| "Can you show me what this looks like end to end?" | Slide 17 — the bank walkthrough, CVE to fixed, with canary and rollback front and center. |
| "What about my own application code?" | Slide 14 — where Lightwell's responsibility ends, and what's still yours. |
| "Why not just use [Chainguard / minimal images]?" | Slide 11 — raw CVE count vs. actual exploitability; Exploit Intelligence. |
| "What's Chainguard doing that we should know about?" | Slide 12 — their trajectory across libraries, IDE, CI/CD, switching cost, dashboards. |
