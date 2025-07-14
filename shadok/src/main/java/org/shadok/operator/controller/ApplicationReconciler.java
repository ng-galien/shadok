package org.shadok.operator.controller;

import io.fabric8.kubernetes.client.KubernetesClient;
import io.javaoperatorsdk.operator.api.reconciler.Context;
import io.javaoperatorsdk.operator.api.reconciler.ControllerConfiguration;
import io.javaoperatorsdk.operator.api.reconciler.Reconciler;
import io.javaoperatorsdk.operator.api.reconciler.UpdateControl;
import jakarta.inject.Inject;
import java.time.Duration;
import java.time.Instant;
import org.shadok.operator.model.application.Application;
import org.shadok.operator.model.application.ApplicationStatus;
import org.shadok.operator.model.cache.DependencyCache;
import org.shadok.operator.model.code.ProjectSource;
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

  @Override
  public UpdateControl<Application> reconcile(
      Application application, Context<Application> context) {
    var name = application.getMetadata().getName();
    var namespace = application.getMetadata().getNamespace();
    var spec = application.getSpec();

    log.info("Reconciling Application: {}/{}", namespace, name);

    try {
      // Vérifier que les ressources référencées existent
      var projectSourceReady = checkProjectSourceReady(spec.projectSourceName(), namespace);
      var dependencyCacheReady = checkDependencyCacheReady(spec.dependencyCacheName(), namespace);

      if (projectSourceReady && dependencyCacheReady) {
        return handleReadyState(application);
      } else if (!projectSourceReady && !dependencyCacheReady) {
        return handleMissingBothResources(application);
      } else if (!projectSourceReady) {
        return handleMissingProjectSource(application);
      } else {
        return handleMissingDependencyCache(application);
      }

    } catch (Exception e) {
      log.error("Failed to reconcile Application {}/{}: {}", namespace, name, e.getMessage(), e);
      return handleFailedReconciliation(application, e);
    }
  }

  private boolean checkProjectSourceReady(String projectSourceName, String namespace) {
    try {
      var projectSource =
          client
              .resources(ProjectSource.class)
              .inNamespace(namespace)
              .withName(projectSourceName)
              .get();

      return projectSource != null
          && projectSource.getStatus() != null
          && projectSource.getStatus().getState()
              == org.shadok.operator.model.code.ProjectSourceStatus.State.READY;
    } catch (Exception e) {
      log.warn(
          "Failed to check ProjectSource {}/{}: {}", namespace, projectSourceName, e.getMessage());
      return false;
    }
  }

  private boolean checkDependencyCacheReady(String dependencyCacheName, String namespace) {
    try {
      var dependencyCache =
          client
              .resources(DependencyCache.class)
              .inNamespace(namespace)
              .withName(dependencyCacheName)
              .get();

      return dependencyCache != null
          && dependencyCache.getStatus() != null
          && dependencyCache.getStatus().getState()
              == org.shadok.operator.model.cache.DependencyCacheStatus.State.READY;
    } catch (Exception e) {
      log.warn(
          "Failed to check DependencyCache {}/{}: {}",
          namespace,
          dependencyCacheName,
          e.getMessage());
      return false;
    }
  }

  private UpdateControl<Application> handleReadyState(Application application) {
    var name = application.getMetadata().getName();
    log.info("Application {} is ready - all dependencies are available", name);

    var status =
        new ApplicationStatus(ApplicationStatus.State.READY, "All referenced resources are ready");
    status.setLastReconciled(Instant.now().toString());

    application.setStatus(status);
    return UpdateControl.patchStatus(application);
  }

  private UpdateControl<Application> handleMissingProjectSource(Application application) {
    var spec = application.getSpec();
    var message = "ProjectSource '" + spec.projectSourceName() + "' is not ready";

    return updateStatusAndReschedule(application, ApplicationStatus.State.PENDING, message);
  }

  private UpdateControl<Application> handleMissingDependencyCache(Application application) {
    var spec = application.getSpec();
    var message = "DependencyCache '" + spec.dependencyCacheName() + "' is not ready";

    return updateStatusAndReschedule(application, ApplicationStatus.State.PENDING, message);
  }

  private UpdateControl<Application> handleMissingBothResources(Application application) {
    var spec = application.getSpec();
    var message =
        "Both ProjectSource '"
            + spec.projectSourceName()
            + "' and DependencyCache '"
            + spec.dependencyCacheName()
            + "' are not ready";

    return updateStatusAndReschedule(application, ApplicationStatus.State.PENDING, message);
  }

  private UpdateControl<Application> handleFailedReconciliation(
      Application application, Exception error) {
    var status =
        new ApplicationStatus(
            ApplicationStatus.State.FAILED, "Reconciliation failed: " + error.getMessage());
    status.setErrorMessage(error.getMessage());

    application.setStatus(status);
    return UpdateControl.patchStatus(application);
  }

  private UpdateControl<Application> updateStatusAndReschedule(
      Application application, ApplicationStatus.State state, String message) {

    var status = new ApplicationStatus(state, message);
    application.setStatus(status);

    return UpdateControl.<Application>patchStatus(application)
        .rescheduleAfter(Duration.ofSeconds(15));
  }
}
