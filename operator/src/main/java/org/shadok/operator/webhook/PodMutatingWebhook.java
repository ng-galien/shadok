package org.shadok.operator.webhook;

import io.fabric8.kubernetes.api.model.*;
import io.fabric8.kubernetes.api.model.admission.v1.AdmissionReview;
import io.fabric8.kubernetes.client.KubernetesClient;
import io.javaoperatorsdk.webhook.admission.AdmissionController;
import io.javaoperatorsdk.webhook.admission.Operation;
import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import java.util.*;
import java.util.function.Consumer;
import java.util.function.Function;
import java.util.function.Predicate;
import java.util.function.UnaryOperator;
import java.util.stream.Stream;
import org.shadok.operator.model.ApplicationType;
import org.shadok.operator.model.InitContainerMountSpec;
import org.shadok.operator.model.application.Application;
import org.shadok.operator.model.application.ApplicationSpec;
import org.shadok.operator.model.cache.DependencyCache;
import org.shadok.operator.model.code.ProjectSource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@Path("/mutate-pods")
@Consumes("application/json")
@Produces("application/json")
public class PodMutatingWebhook {

  private static final Logger log = LoggerFactory.getLogger(PodMutatingWebhook.class);
  // 🔌 Fabric8 client injected by Quarkus/Spring runtime
  @Inject KubernetesClient client;

  private static final String ANNOTATION_CONFIG = "org.shadok/application";

  @POST
  public AdmissionReview mutate(AdmissionReview req) {
    log.info("🚀 Received Pod mutation request: {}", req.getRequest().getUid());
    return admissionController().handle(req);
  }

  private AdmissionController<Pod> admissionController() {
    return new AdmissionController<>(
        (pod, operation) ->
            Optional.of(operation)
                .filter(isCreateOp)
                .flatMap(op -> findAnnotation.apply(pod))
                .flatMap(findAppSpec(client))
                .map(mutateOp)
                .map(mutator -> mutator.apply(pod))
                .orElse(pod));
  }

  Predicate<Operation> isCreateOp = op -> op == Operation.CREATE;

  record CrdRef(String name, String nameSpace) {}

  Function<Pod, Optional<CrdRef>> findAnnotation =
      pod ->
          Optional.ofNullable(pod)
              .flatMap(p -> Optional.ofNullable(p.getMetadata()))
              .flatMap(meta -> Optional.ofNullable(meta.getAnnotations()))
              .flatMap(annotations -> Optional.ofNullable(annotations.get(ANNOTATION_CONFIG)))
              .filter(name -> !name.isEmpty())
              .map(name -> new CrdRef(name, pod.getMetadata().getNamespace()));

  Function<CrdRef, Optional<ApplicationSpec>> findAppSpec(KubernetesClient kubernetesClient) {
    return ref ->
        Optional.ofNullable(
                kubernetesClient
                    .resources(Application.class)
                    .inNamespace(ref.nameSpace())
                    .withName(ref.name)
                    .get())
            .map(Application::getSpec);
  }

  Function<ApplicationSpec, UnaryOperator<Pod>> mutateOp =
      appSpec ->
          pod -> {
            var mutationContext = createMutationContext(appSpec, pod);
            return applyMutations(pod, mutationContext);
          };

  // ADT to model different types of mutations
  public sealed interface PodMutation
      permits PodMutation.AddInitContainer,
          PodMutation.AddVolume,
          PodMutation.AddVolumeMount,
          PodMutation.StartupProbe,
          PodMutation.TransformMainContainer {

    record AddVolume(String name, Volume volume) implements PodMutation {}

    record AddVolumeMount(String containerName, VolumeMount mount) implements PodMutation {}

    record AddInitContainer(Container initContainer) implements PodMutation {}

    record TransformMainContainer(UnaryOperator<Container> transformation) implements PodMutation {}

    record StartupProbe(String containerName) implements PodMutation {}
  }

  // Mutation context containing all necessary information
  record MutationContext(
      ApplicationSpec appSpec,
      Optional<ProjectSource> projectSource,
      Optional<DependencyCache> dependencyCache,
      ApplicationType applicationType,
      List<PodMutation> mutations) {}

  private MutationContext createMutationContext(ApplicationSpec appSpec, Pod pod) {
    var projectSource =
        findProjectSource(appSpec.projectSourceName(), pod.getMetadata().getNamespace());
    var dependencyCache =
        findDependencyCache(appSpec.dependencyCacheName(), pod.getMetadata().getNamespace());
    var applicationType = appSpec.applicationType();

    var mutations =
        Stream.of(
                createVolumeMutations(projectSource, dependencyCache),
                createInitContainerMutations(appSpec, projectSource),
                createMainContainerMutations(appSpec, pod))
            .flatMap(List::stream)
            .toList();

    return new MutationContext(appSpec, projectSource, dependencyCache, applicationType, mutations);
  }

  private Pod applyMutations(Pod pod, MutationContext context) {
    return context.mutations().stream().reduce(pod, this::applyMutation, (p1, p2) -> p2);
  }

  private Pod applyMutation(Pod pod, PodMutation mutation) {
    return switch (mutation) {
      case PodMutation.AddVolume(var name, var volume) -> addVolume(pod, volume);
      case PodMutation.AddVolumeMount(var containerName, var mount) ->
          addVolumeMount(pod, containerName, mount);
      case PodMutation.AddInitContainer(var initContainer) -> addInitContainer(pod, initContainer);
      case PodMutation.TransformMainContainer(var transformation) ->
          transformMainContainer(pod, transformation);
      case PodMutation.StartupProbe(var containerName) -> {
        Consumer<Probe> increaseStartupProbeTimeout =
            probe -> {
              // Logic to increase startup probe timeout
              probe.setInitialDelaySeconds(30);
              probe.setPeriodSeconds(10);
              probe.setFailureThreshold(50);
            };
        pod.getSpec().getContainers().stream()
            .filter(container -> container.getName().equals(containerName))
            .findFirst()
            .map(Container::getStartupProbe)
            .ifPresent(increaseStartupProbeTimeout);
        yield pod;
      }
    };
  }

  // Functions for creating mutations
  private List<PodMutation> createVolumeMutations(
      Optional<ProjectSource> projectSource, Optional<DependencyCache> dependencyCache) {
    return Stream.of(
            Optional.of(createConfigGradleConfigMapVolumeMutation()),
            projectSource.map(this::createTemporaryBuildVolumeMutation),
            projectSource.map(this::createProjectSourceVolumeMutation),
            dependencyCache.map(this::createDependencyCacheVolumeMutation))
        .filter(Optional::isPresent)
        .map(Optional::get)
        .toList();
  }

  private PodMutation createProjectSourceVolumeMutation(ProjectSource projectSource) {
    var volume =
        new VolumeBuilder()
            .withName("project-source")
            .withPersistentVolumeClaim(
                new PersistentVolumeClaimVolumeSourceBuilder()
                    .withClaimName(projectSource.getSpec().pvcName())
                    .withReadOnly(true)
                    .build())
            .build();
    return new PodMutation.AddVolume("project-source", volume);
  }

  private PodMutation createTemporaryBuildVolumeMutation(ProjectSource projectSource) {
    var volume =
        new VolumeBuilder()
            .withName("temporary-build")
            .withEmptyDir(new EmptyDirVolumeSourceBuilder().build())
            .build();
    return new PodMutation.AddVolume("temporary-build", volume);
  }

  private PodMutation createDependencyCacheVolumeMutation(DependencyCache dependencyCache) {
    var volume =
        new VolumeBuilder()
            .withName("dependency-cache")
            .withPersistentVolumeClaim(
                new PersistentVolumeClaimVolumeSourceBuilder()
                    .withClaimName(dependencyCache.getSpec().pvcName())
                    .withReadOnly(false)
                    .build())
            .build();
    return new PodMutation.AddVolume("dependency-cache", volume);
  }

  private PodMutation createConfigGradleConfigMapVolumeMutation() {
    var volume =
        new VolumeBuilder()
            .withName("init-scripts")
            .withConfigMap(
                new ConfigMapVolumeSourceBuilder()
                    .withName("gradle-builddir-config")
                    .withItems(
                        new KeyToPathBuilder()
                            .withKey("buildDir.gradle")
                            .withPath("buildDir.gradle")
                            .build())
                    .build())
            .build();
    return new PodMutation.AddVolume("init-scripts", volume);
  }

  private List<PodMutation> createInitContainerMutations(
      ApplicationSpec appSpec, Optional<ProjectSource> projectSource) {
    return appSpec.initContainerMounts().stream()
        .map(mount -> createInitContainerMutation(mount, projectSource))
        .filter(Optional::isPresent)
        .map(Optional::get)
        .toList();
  }

  private Optional<PodMutation> createInitContainerMutation(
      InitContainerMountSpec mountSpec, Optional<ProjectSource> projectSource) {
    return projectSource.map(
        ps -> {
          var volumeMount =
              new VolumeMountBuilder()
                  .withName("project-source")
                  .withMountPath(mountSpec.mountPath())
                  .withSubPath(mountSpec.subPath())
                  .withReadOnly(true)
                  .build();

          var initContainer =
              new ContainerBuilder()
                  .withName(mountSpec.name())
                  .withImage(getInitContainerImage(mountSpec))
                  .withVolumeMounts(volumeMount)
                  .build();

          return new PodMutation.AddInitContainer(initContainer);
        });
  }

  private List<PodMutation> createMainContainerMutations(ApplicationSpec appSpec, Pod pod) {
    // Logic for finding the target container name based on ApplicationSpec
    String targetContainerName = determineTargetContainerName(appSpec, pod);

    return List.of(
        new PodMutation.StartupProbe(targetContainerName),
        new PodMutation.TransformMainContainer(
            container -> transformForLiveReload(container, appSpec.applicationType())),
        new PodMutation.AddVolumeMount(targetContainerName, createTemporaryBuildVolumeMount()),
        new PodMutation.AddVolumeMount(targetContainerName, createProjectSourceVolumeMount()),
        new PodMutation.AddVolumeMount(targetContainerName, createGradleIinitVolume()),
        new PodMutation.AddVolumeMount(targetContainerName, createDependencyCacheVolumeMount()));
  }

  /**
   * Determine the target container name based on ApplicationSpec configuration.
   *
   * @param appSpec Application specification containing optional containerName
   * @param pod Pod being mutated
   * @return Name of the target container
   * @throws RuntimeException if container resolution fails
   */
  private String determineTargetContainerName(ApplicationSpec appSpec, Pod pod) {
    List<Container> containers = pod.getSpec().getContainers();

    if (appSpec.containerName() != null) {
      // Container name is specified in ApplicationSpec - find it
      return containers.stream()
          .filter(container -> appSpec.containerName().equals(container.getName()))
          .findFirst()
          .map(Container::getName)
          .orElseThrow(
              () ->
                  new RuntimeException(
                      "Container '"
                          + appSpec.containerName()
                          + "' not found in pod. Available containers: "
                          + containers.stream().map(Container::getName).toList()));
    } else {
      // No container name specified - use first container if there's exactly one
      if (containers.isEmpty()) {
        throw new RuntimeException("No containers found in pod");
      } else if (containers.size() == 1) {
        return containers.get(0).getName();
      } else {
        throw new RuntimeException(
            "Multiple containers found but no containerName specified in ApplicationSpec. "
                + "Available containers: "
                + containers.stream().map(Container::getName).toList()
                + ". Please specify containerName in the Application CRD.");
      }
    }
  }

  // Functions for applying mutations
  private Pod addVolume(Pod pod, Volume volume) {
    var volumes =
        new ArrayList<>(Optional.ofNullable(pod.getSpec().getVolumes()).orElse(List.of()));
    volumes.add(volume);
    pod.getSpec().setVolumes(volumes);
    return pod;
  }

  private Pod addVolumeMount(Pod pod, String containerName, VolumeMount mount) {
    pod.getSpec().getContainers().stream()
        .filter(container -> containerName.equals(container.getName()))
        .findFirst()
        .ifPresent(
            container -> {
              var mounts =
                  new ArrayList<>(
                      Optional.ofNullable(container.getVolumeMounts()).orElse(List.of()));
              mounts.add(mount);
              container.setVolumeMounts(mounts);
            });
    return pod;
  }

  private Pod addInitContainer(Pod pod, Container initContainer) {
    var initContainers =
        new ArrayList<>(Optional.ofNullable(pod.getSpec().getInitContainers()).orElse(List.of()));
    initContainers.add(initContainer);
    pod.getSpec().setInitContainers(initContainers);
    return pod;
  }

  private Pod transformMainContainer(Pod pod, UnaryOperator<Container> transformation) {
    pod.getSpec().getContainers().stream()
        .findFirst() // First container = main container
        .map(transformation)
        .ifPresent(
            transformedContainer -> pod.getSpec().getContainers().set(0, transformedContainer));
    return pod;
  }

  private Container transformForLiveReload(Container container, ApplicationType applicationType) {
    var liveReloadConfig = getLiveReloadConfig(applicationType);

    return new ContainerBuilder(container)
        .withCommand(liveReloadConfig.command())
        .withEnv(
            Stream.concat(
                    Optional.ofNullable(container.getEnv()).orElse(List.of()).stream(),
                    liveReloadConfig.envVars().stream())
                .toList())
        .withPorts(
            Stream.concat(
                    Optional.ofNullable(container.getPorts()).orElse(List.of()).stream(),
                    liveReloadConfig.debugPorts().stream())
                .toList())
        .withWorkingDir("/workspace")
        .build();
  }

  // Live-reload configuration per application type
  record LiveReloadConfig(
      List<String> command, List<EnvVar> envVars, List<ContainerPort> debugPorts) {}

  private LiveReloadConfig getLiveReloadConfig(ApplicationType applicationType) {
    return switch (applicationType) {
      case SPRING_MAVEN ->
          new LiveReloadConfig(
              List.of("mvn", "spring-boot:run"),
              List.of(
                  new EnvVarBuilder()
                      .withName("MAVEN_OPTS")
                      .withValue("-Dmaven.repo.local=/cache/.m2/repository")
                      .build(),
                  new EnvVarBuilder()
                      .withName("JAVA_TOOL_OPTIONS")
                      .withValue(
                          "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005")
                      .build()),
              List.of(
                  new ContainerPortBuilder().withContainerPort(5005).withName("debug").build()));
      case SPRING_GRADLE ->
          new LiveReloadConfig(
              List.of("./gradlew", "bootRun"),
              List.of(
                  new EnvVarBuilder()
                      .withName("GRADLE_USER_HOME")
                      .withValue("/cache/.gradle")
                      .build(),
                  new EnvVarBuilder()
                      .withName("JAVA_TOOL_OPTIONS")
                      .withValue(
                          "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005")
                      .build()),
              List.of(
                  new ContainerPortBuilder().withContainerPort(5005).withName("debug").build()));
      case QUARKUS_MAVEN ->
          new LiveReloadConfig(
              List.of("mvn", "quarkus:dev"),
              List.of(
                  new EnvVarBuilder()
                      .withName("MAVEN_OPTS")
                      .withValue("-Dmaven.repo.local=/cache/.m2/repository")
                      .build(),
                  new EnvVarBuilder()
                      .withName("JAVA_TOOL_OPTIONS")
                      .withValue(
                          "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005")
                      .build()),
              List.of(
                  new ContainerPortBuilder().withContainerPort(5005).withName("debug").build()));
      case QUARKUS_GRADLE ->
          new LiveReloadConfig(
              List.of(
                  "./gradlew",
                  "-I",
                  "/cache/init/buildDir.gradle",
                  "--project-cache-dir",
                  "/build/project/.gradle",
                  "--info",
                  "--no-daemon",
                  "quarkusDev"),
              List.of(
                  new EnvVarBuilder()
                      .withName("GRADLE_USER_HOME")
                      .withValue("/cache/.gradle")
                      .build(),
                  new EnvVarBuilder()
                      .withName("GRADLE_OPTS")
                      .withValue("-Dorg.gradle.project.cache.dir=/build/.gradle")
                      .build()),
              List.of(
                  new ContainerPortBuilder().withContainerPort(5005).withName("debug").build()));
      case NODE_NPM, REACT_NPM, NEXTJS_NPM, VUE_NPM, ANGULAR_NPM ->
          new LiveReloadConfig(
              List.of("npm", "run", "dev"),
              List.of(new EnvVarBuilder().withName("NODE_ENV").withValue("development").build()),
              List.of(
                  new ContainerPortBuilder().withContainerPort(9229).withName("debug").build()));
      case NODE_YARN, REACT_YARN, NEXTJS_YARN, VUE_YARN, ANGULAR_YARN ->
          new LiveReloadConfig(
              List.of("yarn", "dev"),
              List.of(new EnvVarBuilder().withName("NODE_ENV").withValue("development").build()),
              List.of(
                  new ContainerPortBuilder().withContainerPort(9229).withName("debug").build()));
      case PYTHON_PIP ->
          new LiveReloadConfig(
              List.of("python", "-m", "pip", "install", "-e", ".", "&&", "python", "main.py"),
              List.of(
                  new EnvVarBuilder().withName("PYTHONPATH").withValue("/workspace").build(),
                  new EnvVarBuilder().withName("PIP_CACHE_DIR").withValue("/cache/.pip").build()),
              List.of(
                  new ContainerPortBuilder().withContainerPort(5678).withName("debug").build()));
      case PYTHON_POETRY ->
          new LiveReloadConfig(
              List.of("poetry", "run", "python", "main.py"),
              List.of(
                  new EnvVarBuilder().withName("PYTHONPATH").withValue("/workspace").build(),
                  new EnvVarBuilder()
                      .withName("POETRY_CACHE_DIR")
                      .withValue("/cache/.poetry")
                      .build()),
              List.of(
                  new ContainerPortBuilder().withContainerPort(5678).withName("debug").build()));
      case DJANGO_PIP ->
          new LiveReloadConfig(
              List.of("python", "manage.py", "runserver", "0.0.0.0:8080"),
              List.of(
                  new EnvVarBuilder().withName("DEBUG").withValue("True").build(),
                  new EnvVarBuilder().withName("PYTHONPATH").withValue("/workspace").build(),
                  new EnvVarBuilder().withName("PIP_CACHE_DIR").withValue("/cache/.pip").build()),
              List.of(
                  new ContainerPortBuilder().withContainerPort(5678).withName("debug").build()));
      case DJANGO_POETRY ->
          new LiveReloadConfig(
              List.of("poetry", "run", "python", "manage.py", "runserver", "0.0.0.0:8080"),
              List.of(
                  new EnvVarBuilder().withName("DEBUG").withValue("True").build(),
                  new EnvVarBuilder().withName("PYTHONPATH").withValue("/workspace").build(),
                  new EnvVarBuilder()
                      .withName("POETRY_CACHE_DIR")
                      .withValue("/cache/.poetry")
                      .build()),
              List.of(
                  new ContainerPortBuilder().withContainerPort(5678).withName("debug").build()));
      case FASTAPI_PIP ->
          new LiveReloadConfig(
              List.of("uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--reload"),
              List.of(
                  new EnvVarBuilder().withName("PYTHONPATH").withValue("/workspace").build(),
                  new EnvVarBuilder().withName("PIP_CACHE_DIR").withValue("/cache/.pip").build()),
              List.of(
                  new ContainerPortBuilder().withContainerPort(5678).withName("debug").build()));
      case FASTAPI_POETRY ->
          new LiveReloadConfig(
              List.of(
                  "poetry",
                  "run",
                  "uvicorn",
                  "main:app",
                  "--host",
                  "0.0.0.0",
                  "--port",
                  "8080",
                  "--reload"),
              List.of(
                  new EnvVarBuilder().withName("PYTHONPATH").withValue("/workspace").build(),
                  new EnvVarBuilder()
                      .withName("POETRY_CACHE_DIR")
                      .withValue("/cache/.poetry")
                      .build()),
              List.of(
                  new ContainerPortBuilder().withContainerPort(5678).withName("debug").build()));
      case GO_MOD ->
          new LiveReloadConfig(
              List.of("go", "run", "main.go"),
              List.of(),
              List.of(
                  new ContainerPortBuilder().withContainerPort(40000).withName("debug").build()));
      case RUBY_BUNDLER, RAILS_BUNDLER ->
          new LiveReloadConfig(
              List.of("bundle", "exec", "rails", "server"),
              List.of(),
              List.of(
                  new ContainerPortBuilder().withContainerPort(1234).withName("debug").build()));
      case PHP_COMPOSER ->
          new LiveReloadConfig(
              List.of("php", "-S", "0.0.0.0:8080"),
              List.of(),
              List.of(
                  new ContainerPortBuilder().withContainerPort(9003).withName("debug").build()));
      case DOTNET_NUGET ->
          new LiveReloadConfig(List.of("dotnet", "watch", "run"), List.of(), List.of());
      case JAVA_MAVEN, JAVA_GRADLE, RUST_CARGO, FLUTTER_PUB, CUSTOM ->
          new LiveReloadConfig(List.of(), List.of(), List.of());
    };
  }

  // Utility functions
  private VolumeMount createProjectSourceVolumeMount() {
    return new VolumeMountBuilder()
        .withName("project-source")
        .withMountPath("/workspace")
        .withReadOnly(true)
        .build();
  }

  private VolumeMount createTemporaryBuildVolumeMount() {
    return new VolumeMountBuilder()
        .withName("temporary-build")
        .withMountPath("/build")
        .withReadOnly(false)
        .build();
  }

  private VolumeMount createGradleIinitVolume() {
    return new VolumeMountBuilder()
        .withName("init-scripts")
        .withMountPath("/cache/init")
        .withReadOnly(false)
        .build();
  }

  private VolumeMount createDependencyCacheVolumeMount() {
    return new VolumeMountBuilder()
        .withName("dependency-cache")
        .withMountPath("/cache")
        .withReadOnly(false)
        .build();
  }

  private String getInitContainerImage(InitContainerMountSpec mountSpec) {
    // Default image or configured based on mount type
    return switch (mountSpec.name()) {
      case String name when name.contains("liquibase") -> "liquibase/liquibase:latest";
      case String name when name.contains("flyway") -> "flyway/flyway:latest";
      default -> "busybox:latest";
    };
  }

  private Optional<ProjectSource> findProjectSource(String name, String namespace) {
    return Optional.ofNullable(
        client.resources(ProjectSource.class).inNamespace(namespace).withName(name).get());
  }

  private Optional<DependencyCache> findDependencyCache(String name, String namespace) {
    return Optional.ofNullable(
        client.resources(DependencyCache.class).inNamespace(namespace).withName(name).get());
  }
}
