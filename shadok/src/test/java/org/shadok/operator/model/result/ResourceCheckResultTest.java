package org.shadok.operator.model.result;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.shadok.operator.model.cache.DependencyCache;
import org.shadok.operator.model.code.ProjectSource;

/**
 * Unit tests for ResourceCheckResult and DependencyState.
 *
 * <p>Tests the new functional style error handling and dependency state management.
 */
class ResourceCheckResultTest {

  @Nested
  @DisplayName("ResourceCheckResult tests")
  class ResourceCheckResultTests {

    @Test
    @DisplayName("Ready result should indicate ready state")
    void readyResultShouldIndicateReadyState() {
      var projectSource = new ProjectSource();
      var result = new ResourceCheckResult.Ready<>(projectSource);

      assertTrue(result.isReady());
      assertFalse(result.isPending());
      assertFalse(result.isError());
    }

    @Test
    @DisplayName("NotReady result should indicate pending state")
    void notReadyResultShouldIndicatePendingState() {
      var projectSource = new ProjectSource();
      var result = new ResourceCheckResult.NotReady<>(projectSource, "Still initializing");

      assertFalse(result.isReady());
      assertTrue(result.isPending());
      assertFalse(result.isError());
    }

    @Test
    @DisplayName("NotFound result should indicate error state")
    void notFoundResultShouldIndicateErrorState() {
      var result = new ResourceCheckResult.NotFound<ProjectSource>("test-source", "default");

      assertFalse(result.isReady());
      assertFalse(result.isPending());
      assertTrue(result.isError());
    }

    @Test
    @DisplayName("Failed result should indicate error state")
    void failedResultShouldIndicateErrorState() {
      var exception = new RuntimeException("API error");
      var result = new ResourceCheckResult.Failed<ProjectSource>("Connection failed", exception);

      assertFalse(result.isReady());
      assertFalse(result.isPending());
      assertTrue(result.isError());
    }
  }

  @Nested
  @DisplayName("DependencyState tests")
  class DependencyStateTests {

    @Test
    @DisplayName("Both ready should create BOTH_READY state")
    void bothReadyShouldCreateBothReadyState() {
      var projectResult = new ResourceCheckResult.Ready<>(new ProjectSource());
      var cacheResult = new ResourceCheckResult.Ready<>(new DependencyCache());

      var state = DependencyState.from(projectResult, cacheResult);

      assertEquals(DependencyState.BOTH_READY, state);
    }

    @Test
    @DisplayName("Both not ready should create BOTH_MISSING state")
    void bothNotReadyShouldCreateBothMissingState() {
      var projectResult = new ResourceCheckResult.NotFound<ProjectSource>("test", "default");
      var cacheResult = new ResourceCheckResult.NotFound<DependencyCache>("cache", "default");

      var state = DependencyState.from(projectResult, cacheResult);

      assertEquals(DependencyState.BOTH_MISSING, state);
    }

    @Test
    @DisplayName("Project not ready should create PROJECT_MISSING state")
    void projectNotReadyShouldCreateProjectMissingState() {
      var projectResult = new ResourceCheckResult.NotFound<ProjectSource>("test", "default");
      var cacheResult = new ResourceCheckResult.Ready<>(new DependencyCache());

      var state = DependencyState.from(projectResult, cacheResult);

      assertEquals(DependencyState.PROJECT_MISSING, state);
    }

    @Test
    @DisplayName("Cache not ready should create CACHE_MISSING state")
    void cacheNotReadyShouldCreateCacheMissingState() {
      var projectResult = new ResourceCheckResult.Ready<>(new ProjectSource());
      var cacheResult = new ResourceCheckResult.NotFound<DependencyCache>("cache", "default");

      var state = DependencyState.from(projectResult, cacheResult);

      assertEquals(DependencyState.CACHE_MISSING, state);
    }
  }
}
