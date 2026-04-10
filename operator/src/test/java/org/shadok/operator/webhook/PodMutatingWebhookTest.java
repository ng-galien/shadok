package org.shadok.operator.webhook;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.fabric8.kubernetes.api.model.Container;
import io.fabric8.kubernetes.api.model.ContainerBuilder;
import io.fabric8.kubernetes.api.model.EnvVar;
import io.fabric8.kubernetes.api.model.ObjectMetaBuilder;
import io.fabric8.kubernetes.api.model.Pod;
import io.fabric8.kubernetes.api.model.PodBuilder;
import io.fabric8.kubernetes.api.model.ProbeBuilder;
import io.fabric8.kubernetes.api.model.Volume;
import io.fabric8.kubernetes.api.model.VolumeMount;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.shadok.operator.model.ApplicationType;
import org.shadok.operator.model.InitContainerMountSpec;
import org.shadok.operator.model.application.ApplicationSpec;
import org.shadok.operator.model.cache.DependencyCache;
import org.shadok.operator.model.cache.DependencyCacheSpec;
import org.shadok.operator.model.code.ProjectSource;
import org.shadok.operator.model.code.ProjectSourceSpec;

/**
 * Unit tests for {@link PodMutatingWebhook} happy paths on the three priority stacks:
 * Quarkus+Gradle, Spring+Maven, Node+NPM.
 *
 * <p>These tests exercise the pure mutation path ({@code mutatePod}) with already-resolved CRD
 * references, so no Kubernetes client or mock server is required.
 */
class PodMutatingWebhookTest {

  private static final String NAMESPACE = "shadok-test";
  private static final String APP_NAME = "my-app";
  private static final String PROJECT_PVC = "my-app-sources";
  private static final String CACHE_PVC = "shared-cache";
  private static final String MAIN_CONTAINER = "app";

  private PodMutatingWebhook webhook;

  @BeforeEach
  void setUp() {
    webhook = new PodMutatingWebhook();
  }

  @Test
  @DisplayName("Quarkus+Gradle: command, env, debug port, volumes and workspace mount are wired")
  void quarkusGradleHappyPath() {
    var appSpec = applicationSpec(ApplicationType.QUARKUS_GRADLE);
    var pod = inputPod();

    var mutated =
        webhook.mutatePod(
            pod, appSpec, Optional.of(projectSource()), Optional.of(dependencyCache()));

    var mainContainer = findContainer(mutated, MAIN_CONTAINER);

    assertEquals(
        List.of(
            "./gradlew",
            "-I",
            "/cache/init/buildDir.gradle",
            "--project-cache-dir",
            "/build/project/.gradle",
            "--info",
            "--no-daemon",
            "quarkusDev"),
        mainContainer.getCommand(),
        "Gradle command should drive quarkusDev with external buildDir");

    assertEquals("/workspace", mainContainer.getWorkingDir());
    assertEnvVar(mainContainer, "GRADLE_USER_HOME", "/cache/.gradle");
    assertDebugPort(mainContainer, 5005);
    assertPvcVolume(mutated, "project-source", PROJECT_PVC, true);
    assertPvcVolume(mutated, "dependency-cache", CACHE_PVC, false);
    assertContainerMount(mainContainer, "project-source", "/workspace", true);
    assertContainerMount(mainContainer, "dependency-cache", "/cache", false);
    assertContainerMount(mainContainer, "init-scripts", "/cache/init", false);
    assertContainerMount(mainContainer, "temporary-build", "/build", false);
  }

  @Test
  @DisplayName("Spring+Maven: mvn spring-boot:run with maven repo rewired to shared cache")
  void springMavenHappyPath() {
    var appSpec = applicationSpec(ApplicationType.SPRING_MAVEN);
    var pod = inputPod();

    var mutated =
        webhook.mutatePod(
            pod, appSpec, Optional.of(projectSource()), Optional.of(dependencyCache()));

    var mainContainer = findContainer(mutated, MAIN_CONTAINER);

    assertEquals(List.of("mvn", "spring-boot:run"), mainContainer.getCommand());
    assertEquals("/workspace", mainContainer.getWorkingDir());
    assertEnvVar(mainContainer, "MAVEN_OPTS", "-Dmaven.repo.local=/cache/.m2/repository");
    assertEnvVarContains(mainContainer, "JAVA_TOOL_OPTIONS", "jdwp");
    assertDebugPort(mainContainer, 5005);
    assertPvcVolume(mutated, "project-source", PROJECT_PVC, true);
    assertPvcVolume(mutated, "dependency-cache", CACHE_PVC, false);
    assertContainerMount(mainContainer, "project-source", "/workspace", true);
    assertContainerMount(mainContainer, "dependency-cache", "/cache", false);
  }

  @Test
  @DisplayName("Node+NPM: npm run dev with NODE_ENV=development and debug port 9229")
  void nodeNpmHappyPath() {
    var appSpec = applicationSpec(ApplicationType.NODE_NPM);
    var pod = inputPod();

    var mutated =
        webhook.mutatePod(
            pod, appSpec, Optional.of(projectSource()), Optional.of(dependencyCache()));

    var mainContainer = findContainer(mutated, MAIN_CONTAINER);

    assertEquals(List.of("npm", "run", "dev"), mainContainer.getCommand());
    assertEquals("/workspace", mainContainer.getWorkingDir());
    assertEnvVar(mainContainer, "NODE_ENV", "development");
    assertDebugPort(mainContainer, 9229);
    assertPvcVolume(mutated, "project-source", PROJECT_PVC, true);
    assertPvcVolume(mutated, "dependency-cache", CACHE_PVC, false);
    assertContainerMount(mainContainer, "project-source", "/workspace", true);
    assertContainerMount(mainContainer, "dependency-cache", "/cache", false);
  }

  // -------------------- init container mounts --------------------

  @Test
  @DisplayName("initContainerMounts: liquibase mount name resolves to liquibase image")
  void initContainerLiquibaseImage() {
    var mount =
        new InitContainerMountSpec(
            "liquibase-changelog",
            "/liquibase/changelog.xml",
            "src/main/resources/db/migration/changelog.xml");
    var appSpec = applicationSpec(ApplicationType.QUARKUS_GRADLE, null, List.of(mount));

    var mutated =
        webhook.mutatePod(
            inputPod(), appSpec, Optional.of(projectSource()), Optional.of(dependencyCache()));

    var initContainer = findInitContainer(mutated, "liquibase-changelog");
    assertEquals("liquibase/liquibase:latest", initContainer.getImage());
    assertEquals(1, initContainer.getVolumeMounts().size());

    var vm = initContainer.getVolumeMounts().get(0);
    assertEquals("project-source", vm.getName());
    assertEquals("/liquibase/changelog.xml", vm.getMountPath());
    assertEquals("src/main/resources/db/migration/changelog.xml", vm.getSubPath());
    assertTrue(Boolean.TRUE.equals(vm.getReadOnly()), "init container mount should be read-only");
  }

  @Test
  @DisplayName("initContainerMounts: flyway mount name resolves to flyway image")
  void initContainerFlywayImage() {
    var mount =
        new InitContainerMountSpec(
            "flyway-migrations", "/flyway/sql", "src/main/resources/db/migration");
    var appSpec = applicationSpec(ApplicationType.SPRING_MAVEN, null, List.of(mount));

    var mutated =
        webhook.mutatePod(
            inputPod(), appSpec, Optional.of(projectSource()), Optional.of(dependencyCache()));

    var initContainer = findInitContainer(mutated, "flyway-migrations");
    assertEquals("flyway/flyway:latest", initContainer.getImage());
  }

  @Test
  @DisplayName("initContainerMounts: arbitrary mount name falls back to busybox image")
  void initContainerDefaultBusyboxImage() {
    var mount = new InitContainerMountSpec("setup-config", "/config/app.yml", "config/app.yml");
    var appSpec = applicationSpec(ApplicationType.NODE_NPM, null, List.of(mount));

    var mutated =
        webhook.mutatePod(
            inputPod(), appSpec, Optional.of(projectSource()), Optional.of(dependencyCache()));

    var initContainer = findInitContainer(mutated, "setup-config");
    assertEquals("busybox:latest", initContainer.getImage());
  }

  @Test
  @DisplayName("initContainerMounts: multiple mounts create multiple init containers")
  void initContainerMultipleMounts() {
    var liquibase =
        new InitContainerMountSpec(
            "liquibase-changelog", "/liquibase/changelog.xml", "db/changelog.xml");
    var config =
        new InitContainerMountSpec("config-bootstrap", "/config/bootstrap.yml", "config/boot.yml");
    var appSpec = applicationSpec(ApplicationType.QUARKUS_GRADLE, null, List.of(liquibase, config));

    var mutated =
        webhook.mutatePod(
            inputPod(), appSpec, Optional.of(projectSource()), Optional.of(dependencyCache()));

    assertEquals(2, mutated.getSpec().getInitContainers().size());
    findInitContainer(mutated, "liquibase-changelog");
    findInitContainer(mutated, "config-bootstrap");
  }

  // -------------------- multi-container resolution --------------------

  @Test
  @DisplayName("multi-container: containerName=app mutates only 'app', leaves 'sidecar' intact")
  void multiContainerTargetsNamedContainer() {
    var appSpec = applicationSpec(ApplicationType.SPRING_MAVEN, "app", List.of());
    var pod = inputPodWithContainers("sidecar", "app");

    var mutated =
        webhook.mutatePod(
            pod, appSpec, Optional.of(projectSource()), Optional.of(dependencyCache()));

    var app = findContainer(mutated, "app");
    assertEquals(List.of("mvn", "spring-boot:run"), app.getCommand());
    assertEquals("/workspace", app.getWorkingDir());
    assertContainerMount(app, "project-source", "/workspace", true);
    assertContainerMount(app, "dependency-cache", "/cache", false);

    var sidecar = findContainer(mutated, "sidecar");
    assertTrue(
        sidecar.getCommand() == null || sidecar.getCommand().isEmpty(),
        "sidecar command should be untouched");
    assertFalse(
        sidecar.getVolumeMounts().stream().anyMatch(m -> "project-source".equals(m.getName())),
        "sidecar should not receive project-source mount");
    assertFalse(
        sidecar.getVolumeMounts().stream().anyMatch(m -> "dependency-cache".equals(m.getName())),
        "sidecar should not receive dependency-cache mount");
  }

  @Test
  @DisplayName(
      "multi-container: no containerName specified throws with available containers listed")
  void multiContainerWithoutContainerNameThrows() {
    var appSpec = applicationSpec(ApplicationType.SPRING_MAVEN, null, List.of());
    var pod = inputPodWithContainers("sidecar", "app");

    var ex =
        assertThrows(
            RuntimeException.class,
            () ->
                webhook.mutatePod(
                    pod, appSpec, Optional.of(projectSource()), Optional.of(dependencyCache())));

    assertTrue(
        ex.getMessage().contains("containerName"),
        () -> "exception message should mention containerName, was: " + ex.getMessage());
    assertTrue(
        ex.getMessage().contains("sidecar") && ex.getMessage().contains("app"),
        () -> "exception message should list available containers, was: " + ex.getMessage());
  }

  @Test
  @DisplayName(
      "multi-container: containerName that does not exist throws with available containers")
  void multiContainerWithUnknownContainerNameThrows() {
    var appSpec = applicationSpec(ApplicationType.SPRING_MAVEN, "nonexistent", List.of());
    var pod = inputPodWithContainers("sidecar", "app");

    var ex =
        assertThrows(
            RuntimeException.class,
            () ->
                webhook.mutatePod(
                    pod, appSpec, Optional.of(projectSource()), Optional.of(dependencyCache())));

    assertTrue(
        ex.getMessage().contains("nonexistent"),
        () -> "exception should mention the bad container name, was: " + ex.getMessage());
    assertTrue(
        ex.getMessage().contains("sidecar") && ex.getMessage().contains("app"),
        () -> "exception should list available containers, was: " + ex.getMessage());
  }

  // -------------------- missing CRD references --------------------

  @Test
  @DisplayName("missing ProjectSource: PVC volumes are skipped but live-reload command is applied")
  void missingProjectSourceSkipsProjectSourceVolume() {
    var appSpec = applicationSpec(ApplicationType.SPRING_MAVEN);

    var mutated =
        webhook.mutatePod(inputPod(), appSpec, Optional.empty(), Optional.of(dependencyCache()));

    assertFalse(
        hasVolume(mutated, "project-source"),
        "no project-source volume should be added when ProjectSource is missing");
    assertFalse(
        hasVolume(mutated, "temporary-build"),
        "no temporary-build volume should be added when ProjectSource is missing");
    assertTrue(
        hasVolume(mutated, "dependency-cache"), "dependency-cache volume should still be added");

    var mainContainer = findContainer(mutated, MAIN_CONTAINER);
    assertEquals(
        List.of("mvn", "spring-boot:run"),
        mainContainer.getCommand(),
        "live-reload command should still be applied");
    assertEquals("/workspace", mainContainer.getWorkingDir());
  }

  @Test
  @DisplayName(
      "missing DependencyCache: cache volume is skipped but live-reload command is applied")
  void missingDependencyCacheSkipsDependencyCacheVolume() {
    var appSpec = applicationSpec(ApplicationType.QUARKUS_GRADLE);

    var mutated =
        webhook.mutatePod(inputPod(), appSpec, Optional.of(projectSource()), Optional.empty());

    assertFalse(
        hasVolume(mutated, "dependency-cache"),
        "no dependency-cache volume should be added when DependencyCache is missing");
    assertTrue(hasVolume(mutated, "project-source"));
    assertTrue(hasVolume(mutated, "temporary-build"));

    var mainContainer = findContainer(mutated, MAIN_CONTAINER);
    assertEquals(
        List.of(
            "./gradlew",
            "-I",
            "/cache/init/buildDir.gradle",
            "--project-cache-dir",
            "/build/project/.gradle",
            "--info",
            "--no-daemon",
            "quarkusDev"),
        mainContainer.getCommand());
  }

  @Test
  @DisplayName("missing both refs: no PVC volumes, but command and workingDir are still applied")
  void missingBothRefsStillAppliesCommandAndWorkingDir() {
    var appSpec = applicationSpec(ApplicationType.NODE_NPM);

    var mutated = webhook.mutatePod(inputPod(), appSpec, Optional.empty(), Optional.empty());

    assertFalse(hasVolume(mutated, "project-source"));
    assertFalse(hasVolume(mutated, "dependency-cache"));
    assertFalse(hasVolume(mutated, "temporary-build"));
    // init-scripts ConfigMap volume is unconditional and should still be present
    assertTrue(
        hasVolume(mutated, "init-scripts"),
        "init-scripts ConfigMap volume should be added unconditionally");

    var mainContainer = findContainer(mutated, MAIN_CONTAINER);
    assertEquals(List.of("npm", "run", "dev"), mainContainer.getCommand());
    assertEquals("/workspace", mainContainer.getWorkingDir());
  }

  // -------------------- startup probe handling --------------------

  @Test
  @DisplayName("existing startup probe: timeout values are extended for live-reload startup")
  void existingStartupProbeGetsExtendedTimeout() {
    var appSpec = applicationSpec(ApplicationType.SPRING_MAVEN);
    var pod =
        new PodBuilder()
            .withNewMetadata()
            .withName(APP_NAME)
            .withNamespace(NAMESPACE)
            .addToAnnotations("org.shadok/application", APP_NAME)
            .endMetadata()
            .withNewSpec()
            .withContainers(
                new ContainerBuilder()
                    .withName(MAIN_CONTAINER)
                    .withImage("example/app:1.0.0")
                    .withStartupProbe(
                        new ProbeBuilder()
                            .withInitialDelaySeconds(5)
                            .withPeriodSeconds(2)
                            .withFailureThreshold(3)
                            .build())
                    .build())
            .endSpec()
            .build();

    var mutated =
        webhook.mutatePod(
            pod, appSpec, Optional.of(projectSource()), Optional.of(dependencyCache()));

    var probe = findContainer(mutated, MAIN_CONTAINER).getStartupProbe();
    assertNotNull(probe, "startup probe should still exist after mutation");
    assertEquals(30, probe.getInitialDelaySeconds(), "initialDelaySeconds should be bumped to 30");
    assertEquals(10, probe.getPeriodSeconds(), "periodSeconds should be bumped to 10");
    assertEquals(50, probe.getFailureThreshold(), "failureThreshold should be bumped to 50");
  }

  @Test
  @DisplayName("no startup probe: mutation does not crash and does not add a probe")
  void containerWithoutStartupProbeStaysWithoutStartupProbe() {
    var appSpec = applicationSpec(ApplicationType.NODE_NPM);

    var mutated =
        webhook.mutatePod(
            inputPod(), appSpec, Optional.of(projectSource()), Optional.of(dependencyCache()));

    var probe = findContainer(mutated, MAIN_CONTAINER).getStartupProbe();
    // Current behavior: StartupProbe mutation only extends an existing probe, never adds one.
    // If this changes (e.g. to add a default probe when the main container doesn't have one),
    // update this test to assert the new contract.
    assertEquals(null, probe, "no startup probe should be added if the container didn't have one");
  }

  // ----------------------------- fixtures -----------------------------

  private ApplicationSpec applicationSpec(ApplicationType type) {
    return applicationSpec(type, null, List.of());
  }

  private ApplicationSpec applicationSpec(
      ApplicationType type, String containerName, List<InitContainerMountSpec> initMounts) {
    return new ApplicationSpec(
        type, "source-ref", "cache-ref", initMounts, Map.of(), containerName);
  }

  private ProjectSource projectSource() {
    var ps = new ProjectSource();
    ps.setMetadata(new ObjectMetaBuilder().withName("source-ref").withNamespace(NAMESPACE).build());
    ps.setSpec(
        new ProjectSourceSpec(
            "dev-sources-pv", "/sources/my-app", PROJECT_PVC, null, "2Gi", null, Map.of()));
    return ps;
  }

  private DependencyCache dependencyCache() {
    var dc = new DependencyCache();
    dc.setMetadata(new ObjectMetaBuilder().withName("cache-ref").withNamespace(NAMESPACE).build());
    dc.setSpec(
        new DependencyCacheSpec(
            "dev-cache-pv",
            "/cache",
            CACHE_PVC,
            null,
            "5Gi",
            null,
            List.of(),
            List.of(),
            Map.of()));
    return dc;
  }

  private Pod inputPod() {
    return new PodBuilder()
        .withNewMetadata()
        .withName(APP_NAME)
        .withNamespace(NAMESPACE)
        .addToAnnotations("org.shadok/application", APP_NAME)
        .endMetadata()
        .withNewSpec()
        .withContainers(
            new ContainerBuilder()
                .withName(MAIN_CONTAINER)
                .withImage("example/app:1.0.0")
                .addNewPort()
                .withContainerPort(8080)
                .withName("http")
                .endPort()
                .build())
        .endSpec()
        .build();
  }

  private Pod inputPodWithContainers(String... containerNames) {
    var builder =
        new PodBuilder()
            .withNewMetadata()
            .withName(APP_NAME)
            .withNamespace(NAMESPACE)
            .addToAnnotations("org.shadok/application", APP_NAME)
            .endMetadata()
            .withNewSpec();
    for (var name : containerNames) {
      builder =
          builder.addToContainers(
              new ContainerBuilder()
                  .withName(name)
                  .withImage("example/" + name + ":1.0.0")
                  .build());
    }
    return builder.endSpec().build();
  }

  // ----------------------------- assertions -----------------------------

  private Container findContainer(Pod pod, String name) {
    return pod.getSpec().getContainers().stream()
        .filter(c -> name.equals(c.getName()))
        .findFirst()
        .orElseThrow(() -> new AssertionError("Container '" + name + "' not found in pod"));
  }

  private Container findInitContainer(Pod pod, String name) {
    var initContainers = pod.getSpec().getInitContainers();
    assertNotNull(initContainers, "pod should have init containers");
    return initContainers.stream()
        .filter(c -> name.equals(c.getName()))
        .findFirst()
        .orElseThrow(() -> new AssertionError("Init container '" + name + "' not found in pod"));
  }

  private void assertEnvVar(Container container, String name, String expectedValue) {
    var env = findEnv(container, name);
    assertEquals(
        expectedValue,
        env.getValue(),
        () -> "env var " + name + " should equal '" + expectedValue + "'");
  }

  private void assertEnvVarContains(Container container, String name, String needle) {
    var env = findEnv(container, name);
    assertNotNull(env.getValue(), () -> "env var " + name + " should have a value");
    assertTrue(
        env.getValue().contains(needle),
        () ->
            "env var "
                + name
                + " should contain '"
                + needle
                + "' but was '"
                + env.getValue()
                + "'");
  }

  private EnvVar findEnv(Container container, String name) {
    return container.getEnv().stream()
        .filter(e -> name.equals(e.getName()))
        .findFirst()
        .orElseThrow(
            () ->
                new AssertionError(
                    "env var '" + name + "' not found on container " + container.getName()));
  }

  private void assertDebugPort(Container container, int expectedPort) {
    var hasDebug =
        container.getPorts().stream()
            .anyMatch(p -> p.getContainerPort() != null && p.getContainerPort() == expectedPort);
    assertTrue(hasDebug, () -> "container should expose debug port " + expectedPort);
  }

  private void assertPvcVolume(Pod pod, String volumeName, String pvcName, boolean readOnly) {
    var volume = findVolume(pod, volumeName);
    assertNotNull(volume.getPersistentVolumeClaim(), () -> volumeName + " should be a PVC volume");
    assertEquals(
        pvcName,
        volume.getPersistentVolumeClaim().getClaimName(),
        () -> volumeName + " should reference PVC " + pvcName);
    assertEquals(
        readOnly,
        Boolean.TRUE.equals(volume.getPersistentVolumeClaim().getReadOnly()),
        () -> volumeName + " PVC readOnly flag mismatch");
  }

  private Volume findVolume(Pod pod, String volumeName) {
    return pod.getSpec().getVolumes().stream()
        .filter(v -> volumeName.equals(v.getName()))
        .findFirst()
        .orElseThrow(() -> new AssertionError("volume '" + volumeName + "' not found in pod"));
  }

  private boolean hasVolume(Pod pod, String volumeName) {
    var volumes = pod.getSpec().getVolumes();
    return volumes != null && volumes.stream().anyMatch(v -> volumeName.equals(v.getName()));
  }

  private void assertContainerMount(
      Container container, String volumeName, String mountPath, boolean readOnly) {
    var mount = findMount(container, volumeName);
    assertEquals(
        mountPath,
        mount.getMountPath(),
        () -> "mount for " + volumeName + " should be at " + mountPath);
    assertEquals(
        readOnly,
        Boolean.TRUE.equals(mount.getReadOnly()),
        () -> "mount for " + volumeName + " readOnly flag mismatch");
  }

  private VolumeMount findMount(Container container, String volumeName) {
    return container.getVolumeMounts().stream()
        .filter(m -> volumeName.equals(m.getName()))
        .findFirst()
        .orElseThrow(
            () ->
                new AssertionError(
                    "volume mount '"
                        + volumeName
                        + "' not found on container "
                        + container.getName()));
  }
}
