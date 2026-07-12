# Fat JAR vs. Decoupled — the side-by-side demo

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
scripts/build.sh                                  # thin WAR  -> app/target/decoupled-patching-demo.war
( cd app-fat && mvn -q clean package )            # fat  WAR  -> app-fat/target/decoupled-patching-demo-fat.war
```

Prove the difference is real, before you even deploy:

```bash
unzip -l app/target/decoupled-patching-demo.war      | grep -c log4j    # 0  — thin carries no Log4j
unzip -l app-fat/target/decoupled-patching-demo-fat.war | grep -c log4j # >0 — fat bundles it
```

> **Say:** "Same application code — literally the same source directory. The only difference is
> where Log4j lives: outside the thin artifact, inside the fat one. Watch what that does to
> patching."

Deploy both to WildFly. Label each so the app reports which it is:

```bash
# Fat deployment
DEMO_PACKAGING=fat  <start/point WildFly at the fat war>
# Thin deployment (existing setup)
DEMO_PACKAGING=thin vm/setup-wildfly.sh
```

(Simplest live: two WildFly instances, or two context roots. Even running them one at a time and
comparing `/api/version` output side by side is enough — the scoreboard is what lands.)

---

## Act 1 — Patch the Fat JAR (the traditional way)

```bash
scripts/patch-fat.sh
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
vm/patch-vm.sh
```

> "Same CVE, same fix. But here the library is an external module. Automation swaps the module and
> restarts — and watch the WAR checksum: **identical**. The application artifact never changed, so
> its SBOM and signature are still valid. No developer opened the app. No PR to the app repo."

`/api/version` flips to PATCHED — with an unchanged artifact.

---

## Act 3 — The container honesty beat (preempt the "you still rebuild" objection)

On OpenShift, decoupling **does** still rebuild the image — and you should say so plainly. The win
there isn't "no rebuild"; it's "no human, and it's staged safely":

```bash
scripts/demo-openshift.sh
```

> "In containers you can't avoid the rebuild, and we don't pretend to. But the patch arrived as an
> automated version-bump PR — Renovate or Dependabot opened it, nobody wrote it — it ran the same
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
| Source-control change | Manual PR by a developer | Automated PR (Renovate / Dependabot) |
| Developer interrupted? | **Yes** | **No** |

**The one-line close:** "Decoupling doesn't make the rebuild disappear — it makes the *developer*
disappear from the patch path, and keeps the artifact trustworthy while it happens."

---

## What each value looks like on screen (so you can point at it)

- **Toil / automation:** `scripts/patch-fat.sh` prints `[developer]` on every step; `vm/patch-vm.sh`
  and the OpenShift PR flow have none.
- **Provenance:** the fat WAR's checksum changes (new artifact to re-scan); the thin WAR's does not.
- **Rollback:** on the VM, re-run the module swap with the old version; on OpenShift,
  `oc tag ...:vulnerable ...:stable` reverts the fleet in one step.
