# Demo Runbook — what to run, what to say, what they see

Two self-contained acts. **Act 1 (WildFly VM)** is the stronger opener because the "no rebuild"
claim becomes literally undeniable — the WAR's checksum doesn't change. **Act 2 (OpenShift)** then
shows the container-native mechanics: canary and rollback.

Total run time: ~12–15 minutes for both. Each act stands alone if you only have one environment.

---

## Before you start (once)

```bash
scripts/build.sh
```

You'll see it assert **"No Log4j inside the WAR."** Say this out loud — it's the premise for
everything: *the artifact we deploy contains only our code; the vulnerable library is supplied
separately.*

---

## Act 1 — WildFly VM: "patch without a rebuild"

**Setup (once, on the VM):**
```bash
vm/setup-wildfly.sh
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

### Beat 3 — Patch by swapping the module
```bash
vm/patch-vm.sh
```
> **Say:** "Here's the whole point. I'm replacing the Log4j **server module** — the shared library
> — and restarting the server. I am **not** rebuilding the application, not redeploying it, not
> even opening it."

The script prints the WAR's **sha256 before and after** and asserts they're **IDENTICAL**.
Pause on that line — it's the money shot.

### Beat 4 — Show it's fixed
```bash
curl -s http://localhost:8080/api/version | jq .
```
Now `"status": "PATCHED"`, running `2.17.1`. Re-run the callback test from Beat 2 → **silence**.

> **Say:** "Same application, byte for byte. Different library underneath. That's the Thin-WAR +
> shared-module model — and it's exactly how you'd answer 'do you hot-swap jars inside my running
> app server?': no, the fix lands once in the module every deployment references."

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
scripts/cleanup-openshift.sh
```

---

## If something goes sideways (live-demo insurance)

- **Route not resolving yet:** give it 10–20s; `oc get route demo`.
- **Build can't reach Maven Central:** pre-run `scripts/fetch-libs.sh <ver>` on a machine with
  access and commit the two JARs in `openshift/module/` before the talk; the binary build ships them.
- **Probes failing / pod not Ready:** WildFly cold start can exceed the initial delay on a busy
  cluster — bump `initialDelaySeconds` in `deployment.yaml`.
- **`jq` missing:** drop the `| jq .` — the endpoints return readable JSON already.
- **Canary shows no mix:** the Service load-balances per-connection; run the poll a few more times,
  or scale the canary to 2 replicas for a more obvious split on a small fleet.
