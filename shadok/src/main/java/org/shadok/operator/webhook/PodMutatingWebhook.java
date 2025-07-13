package org.shadok.operator.webhook;

import io.fabric8.kubernetes.api.model.*;
import io.fabric8.kubernetes.api.model.admission.v1.AdmissionReview;
import io.fabric8.kubernetes.client.KubernetesClient;
import io.javaoperatorsdk.webhook.admission.AdmissionController;
import io.javaoperatorsdk.webhook.admission.Operation;
import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import java.util.*;
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

@Path("/mutate-pods")
@Consumes("application/json")
@Produces("application/json")
public class PodMutatingWebhook {

  // 🔌 Fabric8 client injected by Quarkus/Spring runtime
  @Inject KubernetesClient client;

  private static final String ANNOTATION_CONFIG = "org.shadok/application";

  @POST
  public AdmissionReview mutate(AdmissionReview req) {
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
      permits PodMutation.AddVolume,
          PodMutation.AddVolumeMount,
          PodMutation.AddInitContainer,
          PodMutation.TransformMainContainer {

    record AddVolume(String name, Volume volume) implements PodMutation {}

    record AddVolumeMount(String containerName, VolumeMount mount) implements PodMutation {}

    record AddInitContainer(Container initContainer) implements PodMutation {}

    record TransformMainContainer(UnaryOperator<Container> transformation) implements PodMutation {}
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
                createMainContainerMutations(applicationType))
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
    };
  }

  // Functions for creating mutations
  private List<PodMutation> createVolumeMutations(
      Optional<ProjectSource> projectSource, Optional<DependencyCache> dependencyCache) {
    return Stream.of(
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

  private List<PodMutation> createMainContainerMutations(ApplicationType applicationType) {
    return List.of(
        new PodMutation.TransformMainContainer(
            container -> transformForLiveReload(container, applicationType)),
        new PodMutation.AddVolumeMount("app", createProjectSourceVolumeMount()),
        new PodMutation.AddVolumeMount("app", createDependencyCacheVolumeMount()));
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
      case SPRING ->
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
      case QUARKUS ->
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
      case NODE ->
          new LiveReloadConfig(
              List.of("npm", "run", "dev"),
              List.of(new EnvVarBuilder().withName("NODE_ENV").withValue("development").build()),
              List.of(
                  new ContainerPortBuilder().withContainerPort(9229).withName("debug").build()));
      case PYTHON ->
          new LiveReloadConfig(
              List.of("python", "manage.py", "runserver", "0.0.0.0:8080"),
              List.of(
                  new EnvVarBuilder().withName("DEBUG").withValue("True").build(),
                  new EnvVarBuilder().withName("PYTHONPATH").withValue("/workspace").build()),
              List.of(
                  new ContainerPortBuilder().withContainerPort(5678).withName("debug").build()));
      case GO ->
          new LiveReloadConfig(
              List.of("go", "run", "main.go"),
              List.of(),
              List.of(
                  new ContainerPortBuilder().withContainerPort(40000).withName("debug").build()));
      case RUBY ->
          new LiveReloadConfig(
              List.of("bundle", "exec", "rails", "server"),
              List.of(),
              List.of(
                  new ContainerPortBuilder().withContainerPort(1234).withName("debug").build()));
      case PHP ->
          new LiveReloadConfig(
              List.of("php", "-S", "0.0.0.0:8080"),
              List.of(),
              List.of(
                  new ContainerPortBuilder().withContainerPort(9003).withName("debug").build()));
      case DOTNET -> new LiveReloadConfig(List.of("dotnet", "watch", "run"), List.of(), List.of());
      case OTHER -> new LiveReloadConfig(List.of(), List.of(), List.of());
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

  private VolumeMount createDependencyCacheVolumeMount() {
    return new VolumeMountBuilder()
        .withName("dependency-cache")
        .withMountPath("/cache/.m2")
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
