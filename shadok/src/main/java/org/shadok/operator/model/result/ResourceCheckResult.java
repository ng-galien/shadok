package org.shadok.operator.model.result;

/**
 * Result type for resource checking operations.
 *
 * <p>This sealed interface provides a type-safe way to handle the different outcomes of checking if
 * a resource exists and is ready.
 */
public sealed interface ResourceCheckResult<T>
    permits ResourceCheckResult.Ready,
        ResourceCheckResult.NotReady,
        ResourceCheckResult.NotFound,
        ResourceCheckResult.Failed {

  /** Resource exists and is ready. */
  record Ready<T>(T resource) implements ResourceCheckResult<T> {}

  /** Resource exists but is not ready yet. */
  record NotReady<T>(T resource, String reason) implements ResourceCheckResult<T> {}

  /** Resource does not exist. */
  record NotFound<T>(String name, String namespace) implements ResourceCheckResult<T> {}

  /** Failed to check resource due to an error. */
  record Failed<T>(String error, Throwable cause) implements ResourceCheckResult<T> {}

  /** Check if the result indicates the resource is ready. */
  default boolean isReady() {
    return this instanceof Ready<T>;
  }

  /** Check if the result indicates the resource exists but is not ready. */
  default boolean isPending() {
    return this instanceof NotReady<T>;
  }

  /** Check if the result indicates an error occurred. */
  default boolean isError() {
    return this instanceof Failed<T> || this instanceof NotFound<T>;
  }
}
