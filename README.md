# Decoupled Patching — Live Demo (OpenShift + WildFly VM)

A hands-on demo of the deck's core claim: **you can patch a vulnerable library without
rebuilding, re-testing, or even reopening the application** — and the mechanics differ by
deployment target, exactly as the "containers vs. VMs" slide argues.

The same thin WAR (which contains **your code only** — no Log4j inside it) runs two ways:

| Target | How the library lives | How you patch it | The "aha" |
|---|---|---|---|
| **WildFly VM** | Log4j in an external **server module** | Swap the module JARs, restart | The WAR's checksum is **identical** before and after — it was never rebuilt |
| **OpenShift** | Log4j in a shared **image layer** | Rebuild the thin layer, **canary**, promote, **rollback** | Only the dependency layer rebuilds; canary + rollback gate the change |

The vulnerability is **Log4Shell (CVE-2021-44228)** — the exact scenario from slide 2. The app
runs Log4j `2.14.1` (vulnerable) and gets patched to `2.17.1`.

> ⚠️ This app is **intentionally vulnerable**. Never deploy it on a public network. The
> vulnerability is demonstrated **safely** (no weaponized exploit). See [`docs/SAFETY.md`](docs/SAFETY.md).

---

## What's in here

```
app/                     The THIN WAR (Jakarta EE / JAX-RS). Log4j is 'provided', never bundled.
app-fat/                 The FAT WAR: same source (shared), but Log4j bundled inside — for contrast
  src/main/java/...      /api/version, /api/log, /api/health
  src/main/webapp/WEB-INF/jboss-deployment-structure.xml   <- sources Log4j from the server module
vm/                      WildFly (VM / app-server) side
  modules/.../module.xml The external, swappable Log4j module (starts at 2.14.1)
  setup-wildfly.sh       Install WildFly + module + deploy the WAR
  patch-vm.sh            THE MONEY SHOT: swap the module, restart, WAR unchanged
openshift/               OpenShift side
  Dockerfile             Layered: shared dependency layer + thin app layer
  buildconfig.yaml       In-cluster binary build (no external registry needed)
  deployment.yaml        Stable Deployment + Service + Route, health probes
  canary.yaml            One patched pod behind the same Service
scripts/                 build.sh, fetch-libs.sh, demo-openshift.sh, patch-fat.sh, callback-listener.py, cleanup
docs/                    DEMO-RUNBOOK.md, FATJAR-VS-DECOUPLED.md (the contrast demo), ARCHITECTURE.md, SAFETY.md
```

---

## Prerequisites

- **Build:** JDK 17+, Maven 3.9+
- **VM side:** a Linux VM with `curl`, `unzip`, JDK 17+ (WildFly is downloaded by the script)
- **OpenShift side:** `oc` logged into a cluster, a project you can build in, plus `jq`
- Outbound access to Maven Central (`repo1.maven.org`) from wherever you fetch the Log4j JARs

---

## Quickstart

```bash
# 0. Build the thin WAR (and prove it contains no Log4j)
scripts/build.sh

# --- OpenShift path ---
oc new-project decoupled-patching-demo    # or: oc project <existing>
scripts/demo-openshift.sh                 # guided, paced walk-through

# --- WildFly VM path (run on the VM) ---
vm/setup-wildfly.sh                        # install + deploy (vulnerable)
/opt/wildfly/bin/standalone.sh -b 0.0.0.0  # start the server
curl -s localhost:8080/api/version | jq .  # -> VULNERABLE
vm/patch-vm.sh                             # swap the module, restart
curl -s localhost:8080/api/version | jq .  # -> PATCHED, and the WAR never changed
```

Full stage script with talk track: **[`docs/DEMO-RUNBOOK.md`](docs/DEMO-RUNBOOK.md)**.

**Selling it against Fat JAR?** The side-by-side runbook and scoreboard are in
**[`docs/FATJAR-VS-DECOUPLED.md`](docs/FATJAR-VS-DECOUPLED.md)** — the honest framing is *who does the
work and whether the artifact stays trustworthy*, not build speed.

---

## A note on Lightwell

Project Lightwell is an early Red Hat program, not something a demo can pull live artifacts
from yet. So the "patched artifact from Lightwell's registry" is represented here by the public
Log4j `2.17.1`, as an **illustrative stand-in only** — Log4j is not confirmed as an entry Lightwell
actually remediates today; it's used because Log4Shell is the most widely recognized CVE for this
story. In production, Lightwell would deliver whatever fix it does cover **backported to your
pinned version**, not a forward release — call both of these out when you present. See
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
