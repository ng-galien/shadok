package org.shadok.operator.model.cache;

import com.fasterxml.jackson.annotation.JsonPropertyDescription;
import org.shadok.operator.model.VolumeMountSpec;

import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

/**
 * Specification for DependencyCache CRD.
 * Defines how to create a PVC for dependency caching that can be shared between applications.
 */
public record DependencyCacheSpec(
    @JsonPropertyDescription("Name of the existing PersistentVolume for the dependency cache")
    String persistentVolumeName,

    @JsonPropertyDescription("Path within the PV where the dependency cache is located")
    String cachePath,

    @JsonPropertyDescription("Name for the PVC to be created")
    String pvcName,

    @JsonPropertyDescription("Storage class for the PVC (optional)")
    String storageClass,

    @JsonPropertyDescription("Storage size for the PVC (e.g., '5Gi', '10Gi')")
    String storageSize,

    @JsonPropertyDescription("Access mode for the PVC (read-write for multiple pods)")
    String accessMode,

    @JsonPropertyDescription("List of ConfigMaps to mount in the dependency cache")
    List<VolumeMountSpec> configMaps,

    @JsonPropertyDescription("List of Secrets to mount in the dependency cache")
    List<VolumeMountSpec> secrets,

    @JsonPropertyDescription("Optional labels to apply to the created PVC")
    Map<String, String> labels
) {
    public DependencyCacheSpec {
        persistentVolumeName = Objects.requireNonNull(persistentVolumeName,
            "persistentVolumeName cannot be null");
        cachePath = Objects.requireNonNull(cachePath,
            "cachePath cannot be null");
        pvcName = Objects.requireNonNull(pvcName,
            "pvcName cannot be null");
        storageSize = Optional.ofNullable(storageSize)
            .orElse("5Gi");
        accessMode = Optional.ofNullable(accessMode)
            .orElse("ReadWriteMany");
        storageClass = Optional.ofNullable(storageClass)
            .orElse("standard");
        configMaps = Optional.ofNullable(configMaps)
            .orElse(List.of());
        secrets = Optional.ofNullable(secrets)
            .orElse(List.of());
        labels = Optional.ofNullable(labels)
            .orElse(Map.of());
    }
}
