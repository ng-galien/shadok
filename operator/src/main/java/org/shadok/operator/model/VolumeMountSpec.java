package org.shadok.operator.model;

import com.fasterxml.jackson.annotation.JsonPropertyDescription;
import java.util.Objects;

public record VolumeMountSpec(
    @JsonPropertyDescription("Name of the ConfigMap or Secret") String name,
    @JsonPropertyDescription("Mount path inside the container") String mountPath,
    @JsonPropertyDescription(
            "Optional key within the ConfigMap or Secret to mount (if not specified, all keys are mounted)")
        String key) {
  public VolumeMountSpec {
    name = Objects.requireNonNull(name, "name cannot be null");
    mountPath = Objects.requireNonNull(mountPath, "mountPath cannot be null");
    key = Objects.requireNonNullElse(key, "");
  }
}
