package org.shadok.operator.model.result;

import org.shadok.operator.model.application.Application;
import org.shadok.operator.model.cache.DependencyCache;
import org.shadok.operator.model.code.ProjectSource;

/**
 * Represents the combined state of application dependencies.
 *
 * <p>This enum provides a type-safe way to handle the different combinations of ProjectSource and
 * DependencyCache readiness states.
 */
public enum DependencyState {
  BOTH_READY,
  BOTH_MISSING,
  PROJECT_MISSING,
  CACHE_MISSING;

  /** Create a DependencyState from the check results of both dependencies. */
  public static DependencyState from(
      ResourceCheckResult<ProjectSource> projectResult,
      ResourceCheckResult<DependencyCache> cacheResult) {

    boolean projectReady = projectResult.isReady();
    boolean cacheReady = cacheResult.isReady();

    if (projectReady && cacheReady) return BOTH_READY;
    if (!projectReady && !cacheReady) return BOTH_MISSING;
    if (!projectReady) return PROJECT_MISSING;
    return CACHE_MISSING;
  }

  /** Get a human-readable description of the dependency state. */
  public String getDescription(Application app) {
    var spec = app.getSpec();
    return switch (this) {
      case BOTH_READY -> "All referenced resources are ready";
      case BOTH_MISSING ->
          "Both ProjectSource '"
              + spec.projectSourceName()
              + "' and DependencyCache '"
              + spec.dependencyCacheName()
              + "' are not ready";
      case PROJECT_MISSING -> "ProjectSource '" + spec.projectSourceName() + "' is not ready";
      case CACHE_MISSING -> "DependencyCache '" + spec.dependencyCacheName() + "' is not ready";
    };
  }
}
