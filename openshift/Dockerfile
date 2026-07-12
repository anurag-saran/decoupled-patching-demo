# Dockerfile — container variant.
#
# Layered on purpose to mirror the deck: the shared DEPENDENCY layer (Log4j module) is
# separate from the thin APP layer (your WAR). When you patch Log4j, only the dependency
# layer changes; the app layer is cache-reused, so the rebuild is fast.
#
# Built as an OpenShift binary build (no build-time internet needed): the Log4j JARs are
# supplied from the build context by scripts/fetch-libs.sh.

FROM quay.io/wildfly/wildfly:31.0.1.Final-jdk17

USER root

# ---- Shared dependency layer: the swappable Log4j module ----------------------
# Changes only when the library is patched. fetch-libs.sh drops the JARs here first.
ENV LOG4J_MODULE=${JBOSS_HOME}/modules/com/redhat/demo/log4j/main
RUN mkdir -p ${LOG4J_MODULE}
COPY openshift/module/module.xml     ${LOG4J_MODULE}/module.xml
COPY openshift/module/log4j-api.jar  ${LOG4J_MODULE}/log4j-api.jar
COPY openshift/module/log4j-core.jar ${LOG4J_MODULE}/log4j-core.jar

# ---- Thin application layer: your code only ----------------------------------
# This is the cache-friendly split — rebuilding the layer above does not rebuild this.
COPY app/target/decoupled-patching-demo.war ${JBOSS_HOME}/standalone/deployments/

# OpenShift runs containers as an arbitrary non-root UID; make the dirs group-writable.
RUN chgrp -R 0 ${JBOSS_HOME} && chmod -R g=u ${JBOSS_HOME}

USER 1001
EXPOSE 8080
CMD ["/opt/jboss/wildfly/bin/standalone.sh", "-b", "0.0.0.0"]
