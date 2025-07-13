package org.shadok.operator.dependent;

import io.fabric8.kubernetes.api.model.PersistentVolumeClaim;
import io.fabric8.kubernetes.api.model.PersistentVolumeClaimBuilder;
import io.fabric8.kubernetes.api.model.Quantity;
import io.javaoperatorsdk.operator.api.reconciler.Context;
import io.javaoperatorsdk.operator.processing.dependent.kubernetes.CRUDKubernetesDependentResource;
import io.javaoperatorsdk.operator.processing.dependent.kubernetes.KubernetesDependent;
import java.util.HashMap;
import java.util.Map;
import org.shadok.operator.model.cache.DependencyCache;

/**
 * DependentResource for managing PersistentVolumeClaim creation based on DependencyCache
 * specifications.
 *
 * <p>This class handles the creation and management of PVCs that bind to existing PVs to provide
 * shared dependency caches.
 */
@KubernetesDependent
public class DependencyCachePvcDependent
    extends CRUDKubernetesDependentResource<PersistentVolumeClaim, DependencyCache> {

  public DependencyCachePvcDependent() {
    super(PersistentVolumeClaim.class);
  }

  @Override
  protected PersistentVolumeClaim desired(
      DependencyCache dependencyCache, Context<DependencyCache> context) {
    var spec = dependencyCache.getSpec();
    var metadata = dependencyCache.getMetadata();

    // Build labels for the PVC
    Map<String, String> labels = new HashMap<>();
    labels.put("app.kubernetes.io/name", "shadok");
    labels.put("app.kubernetes.io/component", "dependency-cache");
    labels.put("app.kubernetes.io/managed-by", "shadok-operator");
    labels.put("shadok.com/dependency-cache", metadata.getName());

    // Add custom labels if specified
    if (spec.labels() != null) {
      labels.putAll(spec.labels());
    }

    return new PersistentVolumeClaimBuilder()
        .withNewMetadata()
        .withName(spec.pvcName())
        .withNamespace(metadata.getNamespace())
        .withLabels(labels)
        .addToAnnotations("shadok.com/cache-path", spec.cachePath())
        .addToAnnotations("shadok.com/pv-name", spec.persistentVolumeName())
        .endMetadata()
        .withNewSpec()
        .withAccessModes(spec.accessMode())
        .withVolumeName(spec.persistentVolumeName())
        .withStorageClassName(spec.storageClass())
        .withNewResources()
        .withRequests(Map.of("storage", new Quantity(spec.storageSize())))
        .endResources()
        .endSpec()
        .build();
  }
}
