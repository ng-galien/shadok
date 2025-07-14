package org.shadok.operator.model;

import com.fasterxml.jackson.annotation.JsonPropertyDescription;
import java.util.Objects;

/**
 * Specification for init container volume mounts. Defines how to mount files from the ProjectSource
 * volume into an init container.
 */
public record InitContainerMountSpec(
    @JsonPropertyDescription("Name of the volume mount") String name,
    @JsonPropertyDescription("Mount path inside the container") String mountPath,
    @JsonPropertyDescription("Sub-path within the volume to mount") String subPath) {
  public InitContainerMountSpec {
    name = Objects.requireNonNull(name, "name cannot be null");
    mountPath = Objects.requireNonNull(mountPath, "mountPath cannot be null");
    subPath = Objects.requireNonNull(subPath, "subPath cannot be null");
  }
}
