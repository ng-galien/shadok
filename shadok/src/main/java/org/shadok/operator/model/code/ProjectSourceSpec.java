package org.shadok.operator.model.code;

import com.fasterxml.jackson.annotation.JsonPropertyDescription;

import java.util.Map;
import java.util.Objects;

/**
 * Specification for ProjectSource CRD.
 * Defines how to create a PVC from a PV and mount project sources.
 */
public record ProjectSourceSpec(
    @JsonPropertyDescription("Name of the existing PersistentVolume containing the sources")
    String persistentVolumeName,

    @JsonPropertyDescription("Path within the PV where the project sources are located")
    String sourcePath,

    @JsonPropertyDescription("Name for the PVC to be created")
    String pvcName,

    @JsonPropertyDescription("Storage class for the PVC (optional)")
    String storageClass,

    @JsonPropertyDescription("Storage size for the PVC (e.g., '1Gi', '500Mi')")
    String storageSize,

    @JsonPropertyDescription("Access mode for the PVC (readonly)")
    String accessMode,

    @JsonPropertyDescription("Optional labels to apply to the created PVC")
    Map<String, String> labels
) {
    public  ProjectSourceSpec {
        persistentVolumeName = Objects.requireNonNull(persistentVolumeName,
            "persistentVolumeName cannot be null");
        sourcePath = Objects.requireNonNull(sourcePath,
            "sourcePath cannot be null");
        pvcName = Objects.requireNonNull(pvcName,
            "pvcName cannot be null");
        storageSize = Objects.requireNonNullElse(storageSize, "1Gi");
        accessMode = Objects.requireNonNullElse(accessMode, "ReadOnlyMany");
        storageClass = Objects.requireNonNullElse(storageClass, "standard");
        labels = Objects.requireNonNullElse(labels, Map.of());
    }
}
