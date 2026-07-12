# Safety & responsible use

This repository contains an **intentionally vulnerable** application for demonstration and
education. Please treat it accordingly.

## What is and isn't here

- **Is here:** an app running a known-vulnerable Log4j (2.14.1), and a *benign* listener that
  records connection attempts.
- **Is NOT here:** any weaponized exploit. There is no malicious LDAP/RMI server, no attacker
  payload, and no Java class designed to be loaded and executed. Remote code execution is **not**
  demonstrated or enabled.

## How the vulnerability is demonstrated (safely)

Log4Shell works because a vulnerable Log4j evaluates `${jndi:ldap://...}` in logged text and calls
out to the given server, which — in a real attack — returns a reference that loads a remote class.

This demo stops at the **first, harmless step**: it only shows that the vulnerable library *reaches
out*. `scripts/callback-listener.py` accepts the inbound TCP connection, prints that it happened,
and closes it. It speaks no LDAP and returns no reference, so there is **no path to code
execution**. After patching, the reach-out no longer occurs. This "did it call back?" technique is
the standard, responsible way security teams demonstrate Log4Shell exposure.

The most reliable proof in the demo doesn't even involve the network: `/api/version` reports the
Log4j version the JVM actually loaded. Vulnerable before the patch, fixed after — with the
application artifact unchanged.

## Operating guidance

- **Do not deploy on a public or shared network.** Run it locally, on an isolated VM, or in a
  non-production, network-restricted OpenShift project.
- **Tear it down after the demo** (`scripts/cleanup-openshift.sh`, and stop/remove the VM server).
- The vulnerable Log4j JARs are downloaded at setup time from Maven Central; they are not committed
  to the repo.
- If you must run the optional callback demo, keep the listener on the **same isolated host/network**
  as the app.

## On "Lightwell"

The patched artifact is represented by public Log4j 2.17.1 as a stand-in. This demo does not
connect to, and makes no live claims about, any Red Hat Lightwell registry or service.
