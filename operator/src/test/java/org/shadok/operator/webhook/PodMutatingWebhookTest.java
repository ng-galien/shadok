package org.shadok.operator.webhook;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.fabric8.kubernetes.api.model.Container;
import io.fabric8.kubernetes.api.model.ContainerBuilder;
import io.fabric8.kubernetes.api.model.EnvVar;
import io.fabric8.kubernetes.api.model.ObjectMetaBuilder;
import io.fabric8.kubernetes.api.model.Pod;
import io.fabric8.kubernetes.api.model.PodBuilder;
import io.fabric8.kubernetes.api.model.Volume;
import io.fabric8.kubernetes.api.model.VolumeMount;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.shadok.operator.model.ApplicationType;
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

  // ----------------------------- fixtures -----------------------------

  private ApplicationSpec applicationSpec(ApplicationType type) {
    return new ApplicationSpec(type, "source-ref", "cache-ref", List.of(), Map.of(), null);
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

  // ----------------------------- assertions -----------------------------

  private Container findContainer(Pod pod, String name) {
    return pod.getSpec().getContainers().stream()
        .filter(c -> name.equals(c.getName()))
        .findFirst()
        .orElseThrow(() -> new AssertionError("Container '" + name + "' not found in pod"));
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
