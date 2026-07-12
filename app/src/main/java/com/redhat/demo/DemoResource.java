package com.redhat.demo;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

/**
 * WARNING: INTENTIONALLY VULNERABLE DEMO APPLICATION - do not deploy on a public network.
 *
 * Identical application code is packaged two ways to contrast them:
 *   - THIN : Log4j is supplied by an external, swappable server module (never bundled here).
 *   - FAT  : Log4j is bundled inside the artifact (the traditional Fat JAR/WAR).
 *
 * Set the environment variable DEMO_PACKAGING=fat|thin so /api/version reports which is which.
 */
@Path("/")
public class DemoResource {

    private static final Logger LOG = LogManager.getLogger(DemoResource.class);

    @GET
    @Path("version")
    @Produces(MediaType.APPLICATION_JSON)
    public Response version() {
        String runtimeVersion = detectLog4jVersion();
        boolean vulnerable = isLog4ShellVulnerable(runtimeVersion);
        String packaging = packaging();
        String note = "thin".equals(packaging)
                ? "THIN: Log4j is served by the external server module - patched by swapping the module, this artifact never changes."
                : "FAT: Log4j is bundled inside this artifact - patching means editing the version, rebuilding, and shipping a new artifact.";
        String json = String.format(
                "{%n" +
                "  \"application\": \"decoupled-patching-demo\",%n" +
                "  \"packaging\": \"%s\",%n" +
                "  \"appBuiltAgainstLog4j\": \"2.14.1\",%n" +
                "  \"log4jRunningNow\": \"%s\",%n" +
                "  \"log4ShellVulnerable\": %s,%n" +
                "  \"status\": \"%s\",%n" +
                "  \"note\": \"%s\"%n" +
                "}%n",
                packaging, runtimeVersion, vulnerable,
                vulnerable ? "VULNERABLE - Log4Shell (CVE-2021-44228)" : "PATCHED - Log4Shell mitigated",
                note);
        LOG.info("Version check served: packaging={} log4j-core={} vulnerable={}", packaging, runtimeVersion, vulnerable);
        return Response.ok(json).build();
    }

    @GET
    @Path("log")
    @Produces(MediaType.APPLICATION_JSON)
    public Response log(@QueryParam("msg") String msg) {
        if (msg == null || msg.isEmpty()) {
            msg = "(empty message)";
        }
        // The classic vulnerable pattern: attacker-influenced content in the logged message.
        LOG.info("Incoming message from user: " + msg);
        String json = String.format(
                "{%n" +
                "  \"logged\": true,%n" +
                "  \"echo\": \"%s\",%n" +
                "  \"log4jRunningNow\": \"%s\",%n" +
                "  \"hint\": \"Check the callback listener (safe demo) or the server log to see whether a lookup fired.\"%n" +
                "}%n",
                msg.replace("\"", "'"), detectLog4jVersion());
        return Response.ok(json).build();
    }

    @GET
    @Path("health")
    @Produces(MediaType.APPLICATION_JSON)
    public Response health() {
        return Response.ok(String.format("{ \"status\": \"UP\", \"log4j\": \"%s\", \"packaging\": \"%s\" }%n",
                detectLog4jVersion(), packaging())).build();
    }

    /** Reports how this app is packaged, from the DEMO_PACKAGING env var (defaults to "thin"). */
    private String packaging() {
        String p = System.getenv("DEMO_PACKAGING");
        return (p == null || p.isBlank()) ? "thin" : p.trim().toLowerCase();
    }

    /** Reads the running Log4j-core version. Tries several strategies so it works both in a
     *  plain servlet container and under JBoss Modules (where getImplementationVersion() is
     *  often null). */
    private String detectLog4jVersion() {
        // 1) The Maven pom.properties bundled inside log4j-core.jar. Reliable under JBoss Modules.
        try (java.io.InputStream in = org.apache.logging.log4j.core.LoggerContext.class
                .getResourceAsStream("/META-INF/maven/org.apache.logging.log4j/log4j-core/pom.properties")) {
            if (in != null) {
                java.util.Properties p = new java.util.Properties();
                p.load(in);
                String v = p.getProperty("version");
                if (v != null && !v.isBlank()) {
                    return v.trim();
                }
            }
        } catch (Throwable ignored) { /* fall through */ }

        // 2) Manifest Implementation-Version (works in plain servlet containers).
        try {
            String v = org.apache.logging.log4j.core.LoggerContext.class
                    .getPackage().getImplementationVersion();
            if (v != null && !v.isBlank()) {
                return v.trim();
            }
        } catch (Throwable ignored) { /* fall through */ }

        // 3) Last resort: parse the version out of the loaded JAR's filename.
        try {
            java.net.URL loc = org.apache.logging.log4j.core.LoggerContext.class
                    .getProtectionDomain().getCodeSource().getLocation();
            if (loc != null) {
                java.util.regex.Matcher m = java.util.regex.Pattern
                        .compile("log4j-core-([0-9][0-9A-Za-z._-]*)\\.jar").matcher(loc.getPath());
                if (m.find()) {
                    return m.group(1);
                }
            }
        } catch (Throwable ignored) { /* fall through */ }

        return "unknown";
    }

    /** Log4Shell (CVE-2021-44228) is mitigated at 2.16.0+; 2.17.0+ closes the full family. */
    private boolean isLog4ShellVulnerable(String version) {
        if (version == null || version.equals("unknown")) {
            return false;
        }
        try {
            String[] p = version.split("[.-]");
            int major = Integer.parseInt(p[0]);
            int minor = p.length > 1 ? Integer.parseInt(p[1]) : 0;
            if (major != 2) {
                return false;
            }
            return minor < 16;
        } catch (Exception e) {
            return false;
        }
    }
}
