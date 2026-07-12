# Architecture & mapping to the deck

## The one idea this demo proves

A security fix to a **borrowed library** should not force a rebuild of **your code**. This demo
makes that literal: the application artifact is a *thin* WAR containing only compiled application
classes; Log4j is supplied externally. Patch the external Log4j, and the application is fixed with
no change to the artifact.

## How each piece maps to the slides

| Deck slide | Shown by |
|---|---|
| **Slide 2** — a one-line fix shouldn't cost a full rebuild | Log4Shell is the CVE; the whole demo is the counter-example |
| **Slide 3** — three layers; build tool still resolves everything | Maven resolves the full graph; only the *output layout* changes (Log4j is `provided`) |
| **Slide 4** — Fat / Thin / Hollow | The WAR is Thin (proven: no Log4j inside it) |
| **Slide 5** — containers vs. VMs | **Same WAR**, two mechanics: module swap (VM) vs. layer rebuild (OpenShift). Also answers the EAR/WAR shared-module question directly |
| **Slide 6** — zero-touch flow | VM path: swap, restart, verified |
| **Slide 15** — verification chain | OpenShift path: health probes (gate), canary (staged rollout), `oc rollout`/tag revert (rollback) |
| **Slide 16 / 17** — trusted software factory, "day at a bank" | Canary → health gate → promote → rollback, done with platform objects |

## Why a Thin WAR + WildFly module (not Spring Boot) on the VM

The WildFly **module** is the cleanest possible demonstration of "the library lives outside the
app." The WAR declares a dependency on module `com.redhat.demo.log4j` via
`jboss-deployment-structure.xml`; the module lives on the server. Swapping the module's JARs and
restarting re-links the running app to the new library — while the WAR on disk is byte-for-byte
unchanged (the scripts prove this with a checksum). This is also the precise, real answer to the
reviewer question *"are you hot-swapping jars inside a deployed archive?"* — no; the fix lands once
in the shared module every deployment references.

`exclude-subsystems` (logging) in `jboss-deployment-structure.xml` keeps WildFly's own logging
subsystem from managing the deployment, so the app uses the module's Log4j directly and the version
swap is unambiguous.

### Why `pom.xml`'s Log4j version doesn't need to change (and doesn't block the patch)

A natural objection: "the patched Log4j is a new version — doesn't `pom.xml` need updating, and
doesn't that force a rebuild?" No, and the reason is what `<scope>provided</scope>` actually does.

`app/pom.xml` pins `log4j.version` to `2.14.1` for exactly one purpose: resolving the API `javac`
compiles against (method signatures on `Logger`, `LogManager`, etc.). Because the scope is
`provided`, Maven excludes the JAR from the packaged WAR entirely — nothing about "2.14.1" is
embedded in the compiled `.class` files. Bytecode calls methods by signature, not by version string.
At runtime none of that Maven metadata is even present; `jboss-deployment-structure.xml` is what
resolves the library, at server-restart time, independent of the build. As long as the patched
version preserves the same public API the WAR was compiled against, the already-compiled WAR runs
against it with zero changes — the same reason patching `libssl.so` via `apt`/`yum` doesn't
recompile every binary linked against it.

This does **not** mean `pom.xml` should be ignored forever. It should eventually catch up to
reality — as its own separate, non-blocking, automated PR (Renovate/Dependabot) — so a developer
who clones the repo six months later builds against what's actually running in production, not
against stale metadata. That PR is paperwork catching up to a fix that already shipped, not a
prerequisite for shipping it.

**The safety condition this depends on:** the module swap is only safe if the patched Log4j is
truly API/ABI-compatible with what the WAR was compiled against — same public surface, internals
fixed. A version that changed a method signature could throw a `NoSuchMethodError` at the exact
code path that hits it, with no compiler available to catch it ahead of time (you never compiled
against the new version). This is precisely why the deck's verification chain requires an
**automated compatibility gate** (an API/ABI diff, e.g. japicmp/revapi) before any module swap
ships, and why Lightwell's promise is specifically a *backport* to your pinned version (security
fix only, same API) rather than a forward release that might carry breaking changes.

## Why the same story rebuilds — with real container mechanics — on OpenShift

A running container's filesystem is immutable by design. There is no VM-style "reach in and swap
a file, then restart to relink" for a long-running container — even `oc rsh` + hand-editing a file
is an anti-pattern, since the change vanishes on reschedule and can't be scanned or attested. So
patching Log4j in containers is **always** build-a-new-image → run new pods → retire old pods.
There is no lighter-weight path, and the demo doesn't pretend otherwise.

**What doesn't change, and why:** `mvn package` runs once, *before* the image build, producing the
WAR in `app/target/`. The `COPY app/target/decoupled-patching-demo.war ...` line in the `Dockerfile`
moves already-built bytes into the image — it does not compile anything. So across a Log4j patch,
the application layer is **copied, not recompiled** — nothing about the app's own code re-executes
Maven or the compiler.

**The Docker cache mechanics, precisely:** the Log4j module sits in a layer *below* the WAR's
`COPY` in the `Dockerfile`. When that lower layer changes, every layer above it — including the
WAR's `COPY` — does get a new layer ID; it is not silently skipped. What makes the rebuild fast
isn't that the app layer is exempt from rebuilding, it's *what kind of work* reruns: a file copy,
not a Maven build with compilation and tests. "Fast" describes the nature of the work, not whether
it happens.

**Where the new version actually comes from:** `scripts/fetch-libs.sh <version>` drops the patched
JARs into `openshift/module/` as unversioned filenames, immediately before the image build. Those
fetched JARs are gitignored in this demo — nothing in source control records which version a given
image was built with. That's fine for a demo; in production you'd want that version identified
somewhere durable (a pipeline parameter, a values file, a Renovate-managed reference) for the same
reproducibility reason `pom.xml` should eventually catch up on the VM side.

**What replaces "restart and relink":** since there's no in-place relink, Kubernetes-native rollout
mechanics substitute for it —
1. **Build** the patched image into a new ImageStream tag (`:patched`).
2. **Canary** — `demo-canary` runs one pod on the new image, sharing the Service with the stable
   fleet, so a slice of live traffic hits it.
3. **Health-gate** — readiness/liveness probes decide whether that pod stays up.
4. **Promote** — move the `:stable` tag to the patched image; OpenShift rolls the Deployment to
   new pods fleet-wide.
5. **Rollback** — move `:stable` back; the fleet reverts in one step, no rebuild needed.

**The compatibility caveat applies here too, with higher stakes.** The container path is only safe
under the same condition as the VM path — API/ABI compatibility with what the WAR was compiled
against. But a bad version promoted without a gate doesn't just affect one restarted JVM; it
replaces every pod in the fleet. That's why canary + health-gate isn't an optional nicety here the
way it might feel on a single VM — it's the only thing between "one pod misbehaves" and "the whole
fleet just broke."

## Version detection (why `/api/version` is trustworthy)

`/api/version` tries three strategies, in order, because a single approach isn't reliable under
JBoss Modules' classloader:

1. **`pom.properties` bundled inside `log4j-core.jar`** (`/META-INF/maven/.../pom.properties`) —
   the primary source. Reliable under JBoss Modules because the module classloader can read
   resources from its own JARs even when manifest attributes don't propagate.
2. **`LoggerContext.class.getPackage().getImplementationVersion()`** — the classic
   `Implementation-Version` manifest read. Works in a plain servlet container; frequently returns
   `null` under JBoss Modules, which is exactly why strategy 1 exists.
3. **The loaded JAR's filename**, parsed as a last resort (`log4j-core-2.17.1.jar` → `2.17.1`).

All three read what the JVM actually loaded at runtime — never anything compiled into the WAR —
which is why the endpoint is trustworthy evidence rather than an assertion.

## The Lightwell stand-in (be honest about this on stage)

The demo patches to public Log4j **2.17.1** (a forward release), as an **illustrative stand-in** —
Log4Shell is the most widely recognized CVE for this kind of story, but Log4j does not currently
appear as a standalone entry in Lightwell's remediated set. Don't imply on stage that this specific
CVE is something Lightwell remediates today; frame it as "here's how the mechanism would work for a
CVE like this one," not "here's Lightwell fixing Log4Shell." In production, Lightwell delivers
whatever fix it does cover **backported to your pinned version** — e.g. a `2.14.x`-with-fix,
precisely so you *don't* inherit new features and a full regression cycle. The demo mechanics
(external module / layer swap, verify, canary, rollback) are the same regardless of which library
is actually involved; only the source and version of the patched artifact differ.

**Artifact naming — unconfirmed, two conflicting signals observed:** Lightwell-backported artifacts
do appear to be distinct, uniquely-versioned coordinates rather than the plain upstream version
string — that part is solid. The *exact* qualifier format is not: one internal source shows a
`.redhat-NNNNN` suffix on the Maven coordinate itself, while another (a portal UI's displayed
"latest release" label) showed `.rhlw-NNNNN` for the same package and version. Those two disagree.
Don't state either pattern as confirmed in a customer-facing setting — say only that backports carry
a distinguishing, trackable qualifier, without committing to its exact shape until Red Hat confirms
it. This is exactly the kind of detail worth checking with the Lightwell team before it goes in
front of a customer.

## Deliberate simplifications

- **Canary** uses two Deployments behind one Service (no extra operators) so it runs on any cluster.
  Production-grade is OpenShift GitOps + Argo Rollouts with automated, health-gated promotion — the
  "trusted software factory." Mention it; don't require it.
- **No real exploit.** Exposure is shown via a benign callback (see `docs/SAFETY.md`).
- **Single library.** Real estates have hundreds of dependencies; the point is the mechanism, which
  is identical at scale (and is exactly what the factory automates).
