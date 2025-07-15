package org.shadok.operator.model.application;

import com.fasterxml.jackson.annotation.JsonPropertyDescription;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import org.shadok.operator.model.ApplicationType;
import org.shadok.operator.model.InitContainerMountSpec;

/**
 * Specification for Application CRD. Defines the application type and references to ProjectSource
 * and DependencyCache.
 */
public record ApplicationSpec(
    @JsonPropertyDescription(
            "Type of application combining framework and build system (e.g., SPRING_MAVEN, QUARKUS_GRADLE, NODE_NPM, PYTHON_POETRY)")
        ApplicationType applicationType,
    @JsonPropertyDescription("Reference to the ProjectSource resource name")
        String projectSourceName,
    @JsonPropertyDescription("Reference to the DependencyCache resource name")
        String dependencyCacheName,
    @JsonPropertyDescription(
            "List of volume mounts for init containers from the ProjectSource volume")
        List<InitContainerMountSpec> initContainerMounts,
    @JsonPropertyDescription("Optional labels to apply to resources created by this application")
        Map<String, String> labels,
    @JsonPropertyDescription(
            "Optional name of the main container to mutate. If not specified, uses the first container or raises an error if multiple containers exist")
        String containerName) {
  public ApplicationSpec {
    applicationType = Objects.requireNonNull(applicationType, "applicationType cannot be null");
    projectSourceName =
        Objects.requireNonNull(projectSourceName, "projectSourceName cannot be null");
    dependencyCacheName =
        Objects.requireNonNull(dependencyCacheName, "dependencyCacheName cannot be null");
    initContainerMounts = Objects.requireNonNullElse(initContainerMounts, List.of());
    labels = Objects.requireNonNullElse(labels, Map.of());
    // containerName is optional, can be null
  }
}
