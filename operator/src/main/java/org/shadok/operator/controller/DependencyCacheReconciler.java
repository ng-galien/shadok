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
import org.shadok.operator.dependent.DependencyCachePvcDependent;
import org.shadok.operator.model.cache.DependencyCache;
import org.shadok.operator.model.cache.DependencyCacheStatus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Reconciler for DependencyCache CRD.
 *
 * <p>Manages the lifecycle of dependency cache PVCs by creating them from existing PVs according to
 * the DependencyCache specification.
 */
@ControllerConfiguration(name = "dependency-cache-controller")
@Workflow(dependents = {@Dependent(type = DependencyCachePvcDependent.class)})
public class DependencyCacheReconciler implements Reconciler<DependencyCache> {

  private static final Logger log = LoggerFactory.getLogger(DependencyCacheReconciler.class);

  @Inject DependencyCachePvcDependent pvcDependent;

  @Override
  public UpdateControl<DependencyCache> reconcile(
      DependencyCache dependencyCache, Context<DependencyCache> context) {
    var name = dependencyCache.getMetadata().getName();
    var namespace = dependencyCache.getMetadata().getNamespace();

    log.info("Reconciling DependencyCache: {}/{}", namespace, name);

    try {
      // Check state of dependent PVC
      var pvcResult =
          context.managedWorkflowAndDependentResourceContext().getWorkflowReconcileResult();

      return pvcResult
          .filter(result -> result.allDependentResourcesReady())
          .map(this::handleSuccessfulReconciliation)
          .orElseGet(() -> this.handlePendingReconciliation(dependencyCache));

    } catch (Exception e) {
      log.error(
          "Failed to reconcile DependencyCache {}/{}: {}", namespace, name, e.getMessage(), e);
      return handleFailedReconciliation(dependencyCache, e);
    }
  }

  /** Handle successful reconciliation when all dependent resources are ready. */
  private UpdateControl<DependencyCache> handleSuccessfulReconciliation(Object workflowResult) {
    log.debug("All dependent resources are ready");
    return noUpdate();
  }

  /** Handle pending reconciliation when dependent resources are not yet ready. */
  private UpdateControl<DependencyCache> handlePendingReconciliation(
      DependencyCache dependencyCache) {
    var name = dependencyCache.getMetadata().getName();
    log.info("DependencyCache {} is not ready yet, rescheduling", name);

    // Update status if necessary
    if (dependencyCache.getStatus() == null
        || !DependencyCacheStatus.State.PENDING.equals(dependencyCache.getStatus().getState())) {

      dependencyCache.setStatus(
          new DependencyCacheStatus(DependencyCacheStatus.State.PENDING, "Creating PVC from PV"));

      return UpdateControl.<DependencyCache>patchStatus(dependencyCache)
          .rescheduleAfter(Duration.ofSeconds(10));
    }

    return UpdateControl.<DependencyCache>noUpdate().rescheduleAfter(Duration.ofSeconds(10));
  }

  /** Handle failed reconciliation with appropriate error status. */
  private UpdateControl<DependencyCache> handleFailedReconciliation(
      DependencyCache dependencyCache, Exception error) {
    dependencyCache.setStatus(
        new DependencyCacheStatus(
            DependencyCacheStatus.State.FAILED, "Reconciliation failed: " + error.getMessage()));

    return patchStatus(dependencyCache);
  }
}
