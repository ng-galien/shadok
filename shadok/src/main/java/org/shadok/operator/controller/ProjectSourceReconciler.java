package org.shadok.operator.controller;

import static io.javaoperatorsdk.operator.api.reconciler.UpdateControl.noUpdate;
import static io.javaoperatorsdk.operator.api.reconciler.UpdateControl.patchStatus;

import io.javaoperatorsdk.operator.api.reconciler.Context;
import io.javaoperatorsdk.operator.api.reconciler.ControllerConfiguration;
import io.javaoperatorsdk.operator.api.reconciler.Reconciler;
import io.javaoperatorsdk.operator.api.reconciler.UpdateControl;
import io.javaoperatorsdk.operator.api.reconciler.Workflow;
import io.javaoperatorsdk.operator.api.reconciler.dependent.Dependent;
import jakarta.inject.Inject;
import java.time.Duration;
import org.shadok.operator.dependent.ProjectSourcePvcDependent;
import org.shadok.operator.model.code.ProjectSource;
import org.shadok.operator.model.code.ProjectSourceStatus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Reconciler for ProjectSource CRD.
 *
 * <p>Manages the lifecycle of project source PVCs by creating them from existing PVs according to
 * the ProjectSource specification.
 */
@ControllerConfiguration(name = "project-source-controller")
@Workflow(dependents = {@Dependent(type = ProjectSourcePvcDependent.class)})
public class ProjectSourceReconciler implements Reconciler<ProjectSource> {

  private static final Logger log = LoggerFactory.getLogger(ProjectSourceReconciler.class);

  @Inject ProjectSourcePvcDependent pvcDependent;

  @Override
  public UpdateControl<ProjectSource> reconcile(
      ProjectSource projectSource, Context<ProjectSource> context) {
    var name = projectSource.getMetadata().getName();
    var namespace = projectSource.getMetadata().getNamespace();

    log.info("Reconciling ProjectSource: {}/{}", namespace, name);

    try {
      // Check state of dependent PVC
      var pvcResult =
          context.managedWorkflowAndDependentResourceContext().getWorkflowReconcileResult();

      return pvcResult
          .filter(result -> result.allDependentResourcesReady())
          .map(this::handleSuccessfulReconciliation)
          .orElseGet(() -> this.handlePendingReconciliation(projectSource));

    } catch (Exception e) {
      log.error("Failed to reconcile ProjectSource {}/{}: {}", namespace, name, e.getMessage(), e);
      return handleFailedReconciliation(projectSource, e);
    }
  }

  /** Handle successful reconciliation when all dependent resources are ready. */
  private UpdateControl<ProjectSource> handleSuccessfulReconciliation(Object workflowResult) {
    log.debug("All dependent resources are ready");
    return noUpdate();
  }

  /** Handle pending reconciliation when dependent resources are not yet ready. */
  private UpdateControl<ProjectSource> handlePendingReconciliation(ProjectSource projectSource) {
    var name = projectSource.getMetadata().getName();
    log.info("ProjectSource {} is not ready yet, rescheduling", name);

    // Update status if necessary
    if (projectSource.getStatus() == null
        || !ProjectSourceStatus.State.PENDING.equals(projectSource.getStatus().getState())) {

      projectSource.setStatus(
          new ProjectSourceStatus(ProjectSourceStatus.State.PENDING, "Creating PVC from PV"));

      return UpdateControl.<ProjectSource>patchStatus(projectSource)
          .rescheduleAfter(Duration.ofSeconds(10));
    }

    return UpdateControl.<ProjectSource>noUpdate().rescheduleAfter(Duration.ofSeconds(10));
  }

  /** Handle failed reconciliation with appropriate error status. */
  private UpdateControl<ProjectSource> handleFailedReconciliation(
      ProjectSource projectSource, Exception error) {
    projectSource.setStatus(
        new ProjectSourceStatus(
            ProjectSourceStatus.State.FAILED, "Reconciliation failed: " + error.getMessage()));

    return patchStatus(projectSource);
  }
}
