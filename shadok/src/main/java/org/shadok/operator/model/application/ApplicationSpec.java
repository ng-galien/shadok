package org.shadok.operator.model.application;

import com.fasterxml.jackson.annotation.JsonPropertyDescription;
import org.shadok.operator.model.ApplicationType;
import org.shadok.operator.model.InitContainerMountSpec;

import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * Specification for Application CRD.
 * Defines the application type and references to ProjectSource and DependencyCache.
 */
public record ApplicationSpec(
    @JsonPropertyDescription("Type of application (e.g., SPRING, QUARKUS, NODE, PYTHON)")
    ApplicationType applicationType,

    @JsonPropertyDescription("Reference to the ProjectSource resource name")
    String projectSourceName,

    @JsonPropertyDescription("Reference to the DependencyCache resource name")
    String dependencyCacheName,

    @JsonPropertyDescription("List of volume mounts for init containers from the ProjectSource volume")
    List<InitContainerMountSpec> initContainerMounts,

    @JsonPropertyDescription("Optional labels to apply to resources created by this application")
    Map<String, String> labels
) {
   public ApplicationSpec {
        applicationType = Objects.requireNonNull(applicationType,
            "applicationType cannot be null");
        projectSourceName = Objects.requireNonNull(projectSourceName,
            "projectSourceName cannot be null");
        dependencyCacheName = Objects.requireNonNull(dependencyCacheName,
            "dependencyCacheName cannot be null");
        initContainerMounts = Objects.requireNonNullElse(initContainerMounts, List.of());
        labels = Objects.requireNonNullElse(labels, Map.of());
   }
}
