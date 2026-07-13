# Fat JAR vs. Decoupled — the side-by-side demo

> **Running this live? `scripts/demo-vm.sh` automates this whole runbook** (Fat JAR contrast
> included, on by default) — narrates each step, types the command, then runs it. Read on for
> the detailed manual version and the talk track.

The goal of this demo is **not** "our build is faster." It isn't, meaningfully — you still rebuild
and redeploy either way, and a sharp engineer will call that out. The goal is to make the *real*
costs of a Fat JAR visible: **who does the work, whether the artifact stays trustworthy, and how
you roll back.** Run the same app, packaged two ways, patched for the same CVE, and fill in the
scoreboard live.

> Read `docs/SAFETY.md` first. This app is intentionally vulnerable — keep it off public networks.

---

## Setup (once)

Build both artifacts:

```bash
scripts/demo-vm.sh build_thin                                  # thin WAR  -> app/target/decoupled-patching-demo.war
( cd app-fat && mvn -q clean package )            # fat  WAR  -> app-fat/target/decoupled-patching-demo-fat.war
```

Prove the difference is real, before you even deploy:

```bash
unzip -l app/target/decoupled-patching-demo.war        | grep -iE 'log4j-(api|core).*\.jar'    # (no output) — thin carries no Log4j JAR
unzip -l app-fat/target/decoupled-patching-demo-fat.war | grep -iE 'log4j-(api|core).*\.jar'    # 2 matches  — fat bundles log4j-api + log4j-core
```
> Note: a plain `grep log4j` (no pattern) will also match `log4j2.xml` inside the thin WAR — that's
> just the app's own logging *config* file, not a bundled library, and is expected to be there.
> Use the pattern above (or eyeball the `.jar` suffix) to check for the actual library.

> **Say:** "Same application code — literally the same source directory. The only difference is
> where Log4j lives: outside the thin artifact, inside the fat one. Watch what that does to
> patching."

Deploy one at a time to the same WildFly install — that's simplest and avoids a context-root
clash, since both WARs are configured to serve at `/`:

```bash
# 1) Thin, first (this is what scripts/demo-vm.sh setup_wildfly does by default)
scripts/demo-vm.sh setup_wildfly
DEMO_PACKAGING=thin "${WILDFLY_HOME:-$HOME/wildfly-demo}"/bin/standalone.sh -b 0.0.0.0 &
curl -s localhost:8080/api/version | jq .          # packaging: "thin"
# ... run Act 2 (scripts/demo-vm.sh patch_vm) here, then stop the server (Ctrl-C or kill the job) ...

# 2) Swap in the fat WAR for Act 1
rm -f "${WILDFLY_HOME:-$HOME/wildfly-demo}"/standalone/deployments/decoupled-patching-demo.war*
cp app-fat/target/decoupled-patching-demo-fat.war "${WILDFLY_HOME:-$HOME/wildfly-demo}"/standalone/deployments/
DEMO_PACKAGING=fat "${WILDFLY_HOME:-$HOME/wildfly-demo}"/bin/standalone.sh -b 0.0.0.0 &
curl -s localhost:8080/api/version | jq .          # packaging: "fat"
```

`DEMO_PACKAGING` must be set on the **same command that launches `standalone.sh`** — setting it
on `scripts/demo-vm.sh setup_wildfly` alone does nothing, since that script only installs and deploys; it
never starts the JVM the app actually runs in.

---

## Act 1 — Patch the Fat JAR (the traditional way)

```bash
scripts/demo-vm.sh patch_fat
```

Narrate every line as a **human action**:

> "To patch, a developer edits the version in `pom.xml` — that's a commit, a PR, tracked in source
> control. Then they rebuild the whole artifact. Then they redeploy it. And notice —" (point at the
> checksum) "— the WAR is a **brand-new binary**. Every SBOM, every scan, every signature you had is
> now stale. You start that over. A person did all of this, mid-sprint, for a one-line fix."

`/api/version` flips to PATCHED, but the `note` field reminds you: *the artifact changed.*

---

## Act 2 — Patch the decoupled build (VM / shared module)

```bash
scripts/demo-vm.sh patch_vm
```

> "Same CVE, same fix. But here the library is an external module. Automation swaps the module and
> restarts — and watch the WAR checksum: **identical**. The application artifact never changed, so
> its SBOM and signature are still valid. No developer opened the app. No PR to the app repo."

On a plain dev machine, the script stops the server and prints the restart command — run it:
```bash
DEMO_PACKAGING=thin ~/wildfly-demo/bin/standalone.sh -b 0.0.0.0 &
```
(Java caches the already-loaded library for the life of the process — a fresh process is what
picks up the new module. Still just a restart, not a rebuild; the checksum already proved that.)

`/api/version` flips to PATCHED — with an unchanged artifact.

**Now show the scoreboard's "source-control change" row isn't hand-waving:**
```bash
scripts/demo-vm.sh github_pr
```
> "The app's been running the patched library since the last command — this doesn't fix
> anything, it's the paperwork catching up. Real branch, real commit, styled the way Renovate
> writes them, and it's non-blocking: the fix was already live before this PR even exists."

---

## Act 3 — The container honesty beat (preempt the "you still rebuild" objection)

On OpenShift, decoupling **does** still rebuild the image — and you should say so plainly. The win
there isn't "no rebuild"; it's "no human, and it's staged safely":

```bash
scripts/demo-openshift.sh
```

> "In containers you can't avoid the rebuild, and we don't pretend to. But the patch arrived as an
> automated version-bump PR — Renovate opened it, nobody wrote it — it ran the same
> pipeline, canary-rolled to one pod, health-checked, and can roll back in one step. Same rebuild.
> Zero developer toil. Fully tracked."

---

## The scoreboard (fill this in live)

Notice what is deliberately **not** a row: build time. Don't invite the argument you can't win.

| | **Fat JAR** | **Decoupled + Lightwell** |
|---|---|---|
| Who did the work | A developer, mid-sprint | Automation (bot-opened PR) |
| App artifact changed? | **Yes** — new opaque binary | VM: **no** (identical checksum) · Container: yes, but automated |
| SBOM / provenance | Re-derive from scratch | Per-layer, tracked, signed |
| Rollback | Redeploy a previous full build | Swap the library layer / module back |
| Source-control change | Manual PR by a developer | Automated PR (Renovate — see `scripts/demo-vm.sh github_pr`) |
| Developer interrupted? | **Yes** | **No** |

**The one-line close:** "Decoupling doesn't make the rebuild disappear — it makes the *developer*
disappear from the patch path, and keeps the artifact trustworthy while it happens."

---

## What each value looks like on screen (so you can point at it)

- **Toil / automation:** `scripts/demo-vm.sh patch_fat` prints `[developer]` on every step; `scripts/demo-vm.sh patch_vm`
  and the OpenShift PR flow have none.
- **Provenance:** the fat WAR's checksum changes (new artifact to re-scan); the thin WAR's does not.
- **Rollback:** on the VM, re-run the module swap with the old version; on OpenShift,
  `oc tag ...:vulnerable ...:stable` reverts the fleet in one step.
