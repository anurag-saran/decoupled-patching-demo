# Demo Runbook — what to say, beat by beat

**You run one script per window.** `scripts/demo-vm.sh` and `scripts/demo-openshift.sh` narrate
what they're about to do, type the real command out, run it, then pause and wait for you to
press Enter. **Your only job is knowing what to say at each pause.** That's what this document
is — matched exactly to the order things actually happen when you run the script, not a manual
command list.

Two self-contained acts. **Act 1 (WildFly VM)** is the stronger opener because the "no rebuild"
claim becomes literally undeniable, the WAR's checksum doesn't change. **Act 2 (OpenShift)** then
shows the container-native mechanics: canary and rollback.

Total run time: ~15–18 minutes for both, full length. Each act stands alone if you only have one
environment. Flags to trim it: `DEMO_SKIP_CALLBACK=1`, `DEMO_SKIP_GATE=1`, `DEMO_SKIP_FATJAR=1`
(Act 1 only), `DEMO_AUTOPLAY=1` (auto-advance instead of waiting for Enter — for a timed
recording, not a live talk).

---

## Act 1 — WildFly VM

```bash
scripts/demo-vm.sh
```

### Beat 1 — Build
Screen shows the thin WAR building, then asserting **"No Log4j JAR inside the WAR."**

> **Say:** "That assertion is the premise for everything that follows: the artifact we deploy
> contains only our code. The vulnerable library is supplied separately, and that separation is
> what makes everything else possible."

Next it builds the Fat JAR variant too, same source, and confirms the two artifacts are
genuinely different (`unzip -l` shows Log4j bundled in the fat one, absent from the thin one).

> **Say:** "Same source code, compiled from the exact same directory. The only difference is
> packaging. Hang onto that, it's the whole contrast later in this act."

### Beat 2 — Install and start
WildFly installs (or is reused), the vulnerable Log4j module goes in, the thin WAR deploys, the
server starts.

> **Say (when it starts):** "That start command looks manual, it isn't, the script just ran it
> for you."

### Beat 3 — Confirm it's vulnerable
```
curl -s localhost:8080/api/version | jq .
```
> **Say:** "Read live from the JVM, not a claim on a slide: `2.14.1`, `VULNERABLE`."

### Beat 4 — (Optional) Prove it's reachable, safely
A benign listener starts, a crafted request goes to `/api/log`.

> **Say:** "That listener serves nothing, it just records a connection attempt. Watch: the
> vulnerable Log4j evaluated the lookup and called out. That's the exposure, demonstrated
> without weaponizing anything." *(If "no callback seen" prints instead, say so plainly, don't
> pretend it worked, move on, the vulnerability claim doesn't depend on this one optional step.)*

### Beat 5 — (Optional) The real compatibility gate
Real `japicmp` runs against `2.12.1 → 2.12.2`, a genuine historical Log4j release.

> **Say:** "Before a patch ships, the pipeline runs an actual API/ABI diff, this is real
> japicmp, not a mockup. 2.12.1 to 2.12.2 was Log4j's own emergency backport of the Log4Shell
> fix onto the older Java-7-compatible line, a genuine patch-level, z-stream release, not a
> hypothetical." **Let the verdict print before you say anything about it, don't script the
> answer in advance,** that's the whole credibility of this beat.

Then land the honest limit, however it came out: "This verdict only sees structural changes. A
patch-level release that changes behavior with zero structural fingerprint would still slip
through as a clean fast-lane patch. That's what canary and rollback are for, including for the
patches this rule fast-lanes, not just the ones it flags."

### Beat 6 — Patch by swapping the module
```bash
# the script runs this for you
```
> **Say:** "Here's the whole point. I'm replacing the Log4j **server module**, the shared
> library, and restarting the server. I am not rebuilding the application, not redeploying it,
> not even opening it."

Watch for the **real diff** of the module descriptor:
> **Say:** "Two things change here: the JAR files, and two lines in the module's own config
> pointing at them. That's deliberate, the filename carries the version, so anyone can list this
> directory and know exactly what's deployed without opening a JAR. Note also: this file lives
> on the server. It was never in git, and it never will be, that's not an omission, it's the
> point, the fix and the paperwork are genuinely separate things."

Then the **sha256 before and after, IDENTICAL**. Pause here, it's the money shot.

If the server needed a manual restart (no systemd), say why while it happens: "The files were
already swapped, but Java caches a loaded library for the life of the process, so it takes a
fresh process to actually pick it up. Still not a rebuild, the artifact never changed, the
checksum just proved that."

### Beat 7 — Confirm it's fixed
```
curl -s localhost:8080/api/version | jq .
```
`PATCHED`, running `2.17.1`. If you ran Beat 4, re-run that callback test now → silence.

> **Say:** "Same application, byte for byte. Different library underneath."

### Beat 8 — Name the drift, out loud
```bash
# the script checks this automatically
```
> **Say:** "Real question worth asking: does what's actually running match what source control
> says should be running? Right now, no, the server says 2.17.1, git still says 2.14.1. That's
> configuration drift, one of the least glamorous, most common real problems in production. Here
> it's intentional and temporary, the fix already shipped, git just hasn't caught up, and that's
> exactly what the next step closes. The dangerous version of this same gap is the one nobody
> measures at all."

### Beat 9 — The paperwork catches up, non-blocking
> **Say:** "The app's been running the fix since Beat 6, this step doesn't fix anything, it's
> purely paperwork. Real git branch, real commit, styled the way Renovate actually writes them."

If `gh` is set up, this **actually pushes and opens a real PR**, then puts it on screen in your
browser. Point at the PR page itself, that's the whole reason this path exists over a terminal
diff. It never merges, the PR sits open for review, same as a real one would.

If `gh` isn't available, it falls back to a local branch/commit, say so plainly so nobody thinks
you opened a real PR when you didn't.

> **If asked "is this what Renovate would actually do":** point at `renovate.json` in the repo
> root, real config, not a prop. Security backports (`.rhlw-NNNNN` qualifier) get top priority,
> no schedule restriction; routine updates batch weekly.

### Beat 10 — The Fat JAR contrast
> **Say:** "Now the same CVE, the traditional way." Server redeploys as the fat build,
> vulnerable again, same CVE, different packaging.

Watch the fat patch happen: a developer edits `pom.xml`, rebuilds, redeploys, **and the WAR
checksum changes this time.**

> **Say:** "Compare that to Beat 6. There, a human did nothing but review a PR later; the fix
> was already live. Here, a human has to edit source, rebuild, and redeploy before anything is
> fixed, and the resulting artifact is brand new, so your SBOM and your scan both start over
> from scratch."

WildFly's own deployment scanner picks up the new WAR automatically, no server restart needed
this time, that's a real, useful contrast to name: a full redeploy doesn't need a process
restart the way an in-place module swap does, they're different mechanisms with different
recovery properties.

Confirms `PATCHED` again, different artifact this time.

> **Say (closing this act):** "Same CVE, same fix, two completely different costs. That's the
> whole argument." Point at `docs/FATJAR-VS-DECOUPLED.md` for the scoreboard if anyone wants the
> written version.

---

## Act 2 — OpenShift: canary + rollback

```bash
oc login <cluster>
oc new-project decoupled-patching-demo    # or: oc project <existing>
scripts/demo-openshift.sh
```

| Beat | What happens | What they see | What to say |
|---|---|---|---|
| Prereq check | `oc whoami`, project, `jq` | pass/fail up front | (silent if it passes, no need to narrate) |
| Build vulnerable | `fetch_libs 2.14.1` + `oc start-build` | image builds | "Same thin WAR. Log4j 2.14.1 goes into a shared image layer." |
| Deploy | `oc apply deployment.yaml` | 3 pods, Route up | "`/api/version` says VULNERABLE." |
| **Compatibility gate** | real japicmp on `2.12.1→2.12.2` | a real verdict, not scripted | "Same tool, same real z-stream backport as Act 1. I'm not telling you which way it lands in advance." |
| Rebuild patched | `fetch_libs 2.17.1` + `oc start-build` | **only the dependency layer rebuilds** | "The thin app layer is cache-reused, the rebuild is small and fast. In a container you do rebuild, you just rebuild almost nothing." |
| **Canary** | `oc apply canary.yaml` + poll | traffic split: a **mix** of 2.14.1 and 2.17.1 | "One patched pod, ~25% of live traffic. We watch its health before the fleet moves." |
| **Promote** | move `:stable` tag + poll | **all** 2.17.1 | "Health gate passed. Fleet-wide, rolling, zero downtime." |
| **Drift check** | live `/api/version` vs. `app/pom.xml` | server says 2.17.1, git still says 2.14.1 | "Same drift story as Act 1, named and measured. This script doesn't open a PR itself, `demo-vm.sh`'s github_pr step does exactly that, closing this same gap." |
| **Rollback** | `oc tag vulnerable → stable` | back to 2.14.1 in one step | "The safety net: any regression, one-step revert to the last known-good. The fleet is never stranded." |

> **Tie it back:** "Lightwell supplies the trusted patch; this, the canary, the health gate, the
> rollback, done as policy across the fleet, is the trusted software factory applying it."

**Cleanup:**
```bash
scripts/demo-openshift.sh cleanup
```

---

## If something goes sideways (live-demo insurance)

- **Uncommitted `app/pom.xml` / `app-fat/pom.xml` blocking the PR step:** a previous run's
  version bump was never cleaned up. `scripts/demo-vm.sh reset_pom_versions` fixes it, and a
  full run does this automatically at the start now.
- **Route not resolving yet:** give it 10–20s; `oc get route demo`.
- **`InvalidOutputReference` on an OpenShift build:** the cluster's internal image registry
  probably isn't enabled. Check with `oc get imagestream decoupled-patching-demo -o
  jsonpath='{.status.dockerImageRepository}'`, empty means switch to the Docker Hub path (see
  README's "internal vs. external registry" section).
- **Build/gate steps can't reach Maven Central:** `DEMO_SKIP_GATE=1` skips the japicmp runs;
  pre-fetch the jars on a machine with access otherwise.
- **Probes failing / pod not Ready:** WildFly cold start can exceed the initial delay on a busy
  cluster, bump `initialDelaySeconds` in `deployment.yaml`.
- **`jq` missing:** drop the `| jq .`, the endpoints return readable JSON already.
- **Canary shows no mix:** the Service load-balances per-connection; run the poll a few more
  times, or scale the canary to 2 replicas for a more obvious split on a small fleet.
- **`gh` not installed:** `github_pr` falls back to local-only automatically and tells you so.
  `brew install gh && gh auth login` gets you the real push-and-open-in-browser flow next run.
