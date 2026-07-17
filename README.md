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
vm/
  modules/.../module.xml The external, swappable Log4j module (starts at 2.14.1, versioned filenames)
openshift/               OpenShift side
  Dockerfile             Layered: shared dependency layer + thin app layer
  buildconfig.yaml       In-cluster binary build (no external registry needed)
  deployment.yaml        Stable Deployment + Service + Route, health probes
  canary.yaml            One patched pod behind the same Service
scripts/
  demo-vm.sh             THE ONE SCRIPT for the VM window — build, patch, GitHub PR, Fat JAR contrast
  demo-openshift.sh      THE ONE SCRIPT for the OpenShift window — build, canary, promote, rollback
  lib/demo-fx.sh         Shared narrate/type/run library both scripts source
  callback-listener.py   Benign exploit-reachability listener (Python, used by demo-vm.sh)
docs/                    DEMO-RUNBOOK.md, FATJAR-VS-DECOUPLED.md (the contrast demo), ARCHITECTURE.md, SAFETY.md
renovate.json            Real, valid Renovate config — not a demo prop
```

Both driver scripts are self-contained — each one function per former standalone script, callable
individually for debugging: `scripts/demo-vm.sh <function>` or `scripts/demo-openshift.sh <function>`
runs just that step instead of the full demo (e.g. `scripts/demo-vm.sh patch_fat`).

---

## Prerequisites

- **Build:** JDK 17+, Maven 3.9+
- **VM side:** a Linux VM with `curl`, `unzip`, JDK 17+ (WildFly is downloaded by the script)
- **OpenShift side:** `oc` logged into a cluster, a project you can build in, plus `jq`
- Outbound access to Maven Central (`repo1.maven.org`) from wherever you fetch the Log4j JARs
- **Optional, for the real GitHub PR step:** [`gh`](https://cli.github.com) installed and
  authenticated (`gh auth login`), and a GitHub-hosted `origin` remote. Without these, that step
  automatically falls back to a local-only git branch/commit — nothing breaks either way.

---

## OpenShift: internal vs. external registry

`openshift/buildconfig.yaml` pushes to **an external registry (Docker Hub)** by default — use
this if your cluster has no internal image registry enabled. Diagnose with:
```bash
oc get imagestream decoupled-patching-demo -o jsonpath='{.status.dockerImageRepository}'
```
Empty output confirms no internal registry — use the Docker Hub path below. Non-empty output
means your cluster *does* have one — use `openshift/buildconfig-internal-registry.yaml` instead
(simpler, no external credentials needed): `oc apply -f openshift/buildconfig-internal-registry.yaml`.

**One-time setup for the Docker Hub path** (run these yourself — never share a Docker Hub
credential with an AI or paste it into a script you didn't write yourself):
```bash
oc create secret docker-registry dockerhub-push-secret \
  --docker-server=docker.io \
  --docker-username=<your-dockerhub-username> \
  --docker-password=<your-dockerhub-access-token> \
  --docker-email=<your-email>
oc secrets link builder dockerhub-push-secret
```
Use a Docker Hub **access token**, not your real password — generate one at
[hub.docker.com/settings/security](https://hub.docker.com/settings/security).

Before your first run, edit two places to use your own Docker Hub username/repo instead of the
placeholder:
- `openshift/buildconfig.yaml` → `output.to.name`
- `scripts/demo-openshift.sh` → the `DOCKERHUB_IMAGE` variable near the top

**How the rest of the demo still works unchanged:** `deployment.yaml` and `canary.yaml` still
reference local ImageStreamTags (`decoupled-patching-demo:stable`, `:patched`) — nothing about
canary/promote/rollback changes. Each build now pushes to Docker Hub's `:latest`, then
`oc tag <dockerhub-image>:latest <local-tag> --reference-policy=source` immediately captures that
specific push into a stable local tag before the next build overwrites Docker Hub's `:latest`.
Note the flag value is lowercase (`source`, not `Source`) — `oc` rejects it otherwise.

> This path has been confirmed working end-to-end on a real cluster: push-secret auth, the build,
> and the push to Docker Hub all succeed. The `--reference-policy` case-sensitivity bug above was
> caught and fixed from that same real run — everything past that point (deploy, canary, promote,
> rollback) still needs a full run to confirm, since that first real test stopped at the tag-import
> step.

---

## Quickstart — one script per window

**Window 1 — VM / WildFly (thin patch, compatibility gate, drift check, GitHub PR, Fat JAR contrast):**
```bash
scripts/demo-vm.sh
```
Narrates each step, types the real command out, then runs it. Press Enter to advance.
Flags: `DEMO_SKIP_CALLBACK=1` skips the optional exploit-reachability proof;
`DEMO_SKIP_GATE=1` skips the real japicmp compatibility-gate run (needs internet to Maven
Central); `DEMO_SKIP_FATJAR=1` skips the Fat JAR contrast; `DEMO_AUTOPLAY=1` auto-advances (for a
timed rehearsal or recording instead of a live talk).

**Window 2 — OpenShift (compatibility gate + canary + rollback + drift check):**
```bash
oc new-project decoupled-patching-demo    # or: oc project <existing>
scripts/demo-openshift.sh
```
Same narrate/type/run style, same pacing controls. Before the image rebuild it runs the same
real japicmp compatibility gate as Window 1, `2.12.1 → 2.12.2`, a real historical z-stream
security backport, and after the fleet-wide promote it checks configuration drift (does the
live server match what git says should be running). `DEMO_SKIP_GATE=1` skips the gate here too.

That's it — you only run one script per window; nothing else to type during the demo itself.

Full stage script with talk track: **[`docs/DEMO-RUNBOOK.md`](docs/DEMO-RUNBOOK.md)**.
Want a narrative to open with instead of jumping straight into beats? **[`docs/DEMO-STORY.md`](docs/DEMO-STORY.md)**
frames the whole demo around what actually happened the night Log4Shell broke.

**Selling it against Fat JAR?** The side-by-side runbook and scoreboard are in
**[`docs/FATJAR-VS-DECOUPLED.md`](docs/FATJAR-VS-DECOUPLED.md)** — the honest framing is *who does the
work and whether the artifact stays trustworthy*, not build speed.

---

## The real GitHub PR step

`scripts/demo-vm.sh`'s `github_pr` step is built to demo well against an audience that's used to
seeing GitHub's UI, not just a terminal diff. If `gh` is installed, authenticated, and `origin`
points at GitHub, it will **actually push a branch and open a real PR**, then open it in your
browser (`gh pr view --web`) — the same branch naming and commit style Renovate uses for real. If
any of those prerequisites are missing, it prints exactly which one and falls back to a
local-only branch/commit instead, so the demo never hard-fails either way.

It never auto-merges anything — the PR is left open, exactly as a real Renovate PR would be,
waiting for review.

---

## A note on Lightwell

Project Lightwell is an early Red Hat program, not something a demo can pull live artifacts
from yet. So the "patched artifact from Lightwell's registry" is represented here by the public
Log4j `2.17.1`, as an **illustrative stand-in only** — Log4j is not confirmed as an entry Lightwell
actually remediates today; it's used because Log4Shell is the most widely recognized CVE for this
story. In production, Lightwell would deliver whatever fix it does cover **backported to your
pinned version**, not a forward release — call both of these out when you present. See
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
