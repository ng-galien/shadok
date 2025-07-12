package org.shadok.operator.dependent;

import io.fabric8.kubernetes.api.model.PersistentVolumeClaim;
import io.fabric8.kubernetes.api.model.PersistentVolumeClaimBuilder;
import io.fabric8.kubernetes.api.model.Quantity;
import io.javaoperatorsdk.operator.api.reconciler.Context;
import io.javaoperatorsdk.operator.processing.dependent.kubernetes.CRUDKubernetesDependentResource;
import io.javaoperatorsdk.operator.processing.dependent.kubernetes.KubernetesDependent;
import org.shadok.operator.model.code.ProjectSource;

import java.util.HashMap;
import java.util.Map;

/**
 * DependentResource for managing PersistentVolumeClaim creation
 * based on ProjectSource specifications.
   *
 * This class handles the creation and management of PVCs that bind
 * to existing PVs to mount project sources.
 */
@KubernetesDependent
public class ProjectSourcePvcDependent 
        extends CRUDKubernetesDependentResource<PersistentVolumeClaim, ProjectSource> {

    public ProjectSourcePvcDependent() {
        super(PersistentVolumeClaim.class);
    }

    @Override
    protected PersistentVolumeClaim desired(ProjectSource projectSource, Context<ProjectSource> context) {
        var spec = projectSource.getSpec();
        var metadata = projectSource.getMetadata();

        // Build labels for the PVC
        Map<String, String> labels = new HashMap<>();
        labels.put("app.kubernetes.io/name", "shadok");
        labels.put("app.kubernetes.io/component", "project-source");
        labels.put("app.kubernetes.io/managed-by", "shadok-operator");
        labels.put("shadok.com/project-source", metadata.getName());

        // Add custom labels if specified
        if (spec.labels() != null) {
            labels.putAll(spec.labels());
        }

        return new PersistentVolumeClaimBuilder()
                .withNewMetadata()
                    .withName(spec.pvcName())
                    .withNamespace(metadata.getNamespace())
                    .withLabels(labels)
                    .addToAnnotations("shadok.com/source-path", spec.sourcePath())
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
