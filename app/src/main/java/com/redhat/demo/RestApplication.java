package com.redhat.demo;

import jakarta.ws.rs.ApplicationPath;
import jakarta.ws.rs.core.Application;

/**
 * Activates JAX-RS at /api. RESTEasy (bundled in WildFly) picks this up automatically —
 * no web.xml servlet wiring needed.
 */
@ApplicationPath("/api")
public class RestApplication extends Application {
}
