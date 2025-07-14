package org.shadok.operator.controller;

import static io.javaoperatorsdk.operator.api.reconciler.UpdateControl.patchStatus;
import static java.util.Optional.ofNullable;

import io.fabric8.kubernetes.client.KubernetesClient;
import io.javaoperatorsdk.operator.api.reconciler.Context;
import io.javaoperatorsdk.operator.api.reconciler.ControllerConfiguration;
import io.javaoperatorsdk.operator.api.reconciler.Reconciler;
import io.javaoperatorsdk.operator.api.reconciler.UpdateControl;
import jakarta.inject.Inject;
import java.time.Duration;
import java.time.Instant;
import java.util.function.Function;
import org.shadok.operator.model.application.Application;
import org.shadok.operator.model.application.ApplicationStatus;
import org.shadok.operator.model.cache.DependencyCache;
import org.shadok.operator.model.code.ProjectSource;
import org.shadok.operator.model.result.DependencyState;
import org.shadok.operator.model.result.ResourceCheckResult;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Reconciler for Application CRD.
 *
 * <p>Manages the lifecycle of applications by ensuring that the referenced ProjectSource and
 * DependencyCache resources exist and are ready.
 *
 * <p>This reconciler doesn't create dependent resources directly, but validates that the referenced
 * resources exist and are in a ready state.
 */
@ControllerConfiguration(name = "application-controller")
public class ApplicationReconciler implements Reconciler<Application> {

  private static final Logger log = LoggerFactory.getLogger(ApplicationReconciler.class);

  @Inject KubernetesClient client;

  // Functional style reconciliation logic
  private final Function<Application, UpdateControl<Application>> reconcileLogic =
      app ->
          checkDependencies(app)
              .map(state -> handleDependencyState(app, state))
              .orElseGet(
                  () ->
                      handleFailedReconciliation(
                          app, new RuntimeException("Invalid application state")));

  @Override
  public UpdateControl<Application> reconcile(
      Application application, Context<Application> context) {
    var name = application.getMetadata().getName();
    var namespace = application.getMetadata().getNamespace();

    log.info("Reconciling Application: {}/{}", namespace, name);

    try {
      return reconcileLogic.apply(application);
    } catch (Exception e) {
      log.error("Failed to reconcile Application {}/{}: {}", namespace, name, e.getMessage(), e);
      return handleFailedReconciliation(application, e);
    }
  }

  /** Check the state of all application dependencies. */
  private java.util.Optional<DependencyState> checkDependencies(Application app) {
    var spec = app.getSpec();
    var namespace = app.getMetadata().getNamespace();

    var projectResult = checkProjectSource(spec.projectSourceName(), namespace);
    var cacheResult = checkDependencyCache(spec.dependencyCacheName(), namespace);

    return java.util.Optional.of(DependencyState.from(projectResult, cacheResult));
  }

  /** Handle the application state based on dependency readiness. */
  private UpdateControl<Application> handleDependencyState(Application app, DependencyState state) {
    return switch (state) {
      case BOTH_READY -> handleReadyState(app);
      case BOTH_MISSING, PROJECT_MISSING, CACHE_MISSING -> handlePendingState(app, state);
    };
  }

  /** Check if a ProjectSource exists and is ready. */
  private ResourceCheckResult<ProjectSource> checkProjectSource(String name, String namespace) {
    try {
      return ofNullable(
              client.resources(ProjectSource.class).inNamespace(namespace).withName(name).get())
          .map(
              projectSource -> {
                if (projectSource.getStatus() != null
                    && projectSource.getStatus().getState()
                        == org.shadok.operator.model.code.ProjectSourceStatus.State.READY) {
                  return new ResourceCheckResult.Ready<>(projectSource);
                } else {
                  return new ResourceCheckResult.NotReady<>(
                      projectSource, "ProjectSource not ready");
                }
              })
          .orElse(new ResourceCheckResult.NotFound<>(name, namespace));
    } catch (Exception e) {
      log.warn("Failed to check ProjectSource {}/{}: {}", namespace, name, e.getMessage());
      return new ResourceCheckResult.Failed<>(e.getMessage(), e);
    }
  }

  /** Check if a DependencyCache exists and is ready. */
  private ResourceCheckResult<DependencyCache> checkDependencyCache(String name, String namespace) {
    try {
      return ofNullable(
              client.resources(DependencyCache.class).inNamespace(namespace).withName(name).get())
          .map(
              cache -> {
                if (cache.getStatus() != null
                    && cache.getStatus().getState()
                        == org.shadok.operator.model.cache.DependencyCacheStatus.State.READY) {
                  return new ResourceCheckResult.Ready<>(cache);
                } else {
                  return new ResourceCheckResult.NotReady<>(cache, "DependencyCache not ready");
                }
              })
          .orElse(new ResourceCheckResult.NotFound<>(name, namespace));
    } catch (Exception e) {
      log.warn("Failed to check DependencyCache {}/{}: {}", namespace, name, e.getMessage());
      return new ResourceCheckResult.Failed<>(e.getMessage(), e);
    }
  }

  private UpdateControl<Application> handleReadyState(Application application) {
    var name = application.getMetadata().getName();
    log.info("Application {} is ready - all dependencies are available", name);

    var status =
        new ApplicationStatus(ApplicationStatus.State.READY, "All referenced resources are ready");
    status.setLastReconciled(Instant.now().toString());

    application.setStatus(status);
    return patchStatus(application);
  }

  private UpdateControl<Application> handlePendingState(
      Application application, DependencyState state) {
    var message = state.getDescription(application);
    return updateStatusAndReschedule(application, ApplicationStatus.State.PENDING, message);
  }

  private UpdateControl<Application> handleFailedReconciliation(
      Application application, Exception error) {
    var status =
        new ApplicationStatus(
            ApplicationStatus.State.FAILED, "Reconciliation failed: " + error.getMessage());
    status.setErrorMessage(error.getMessage());

    application.setStatus(status);
    return patchStatus(application);
  }

  private UpdateControl<Application> updateStatusAndReschedule(
      Application application, ApplicationStatus.State state, String message) {

    var status = new ApplicationStatus(state, message);
    application.setStatus(status);

    return UpdateControl.<Application>patchStatus(application)
        .rescheduleAfter(Duration.ofSeconds(15));
  }
}
