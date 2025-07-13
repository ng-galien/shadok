package org.shadok.operator.model.cache;

import com.fasterxml.jackson.annotation.JsonPropertyDescription;

/** Status for DependencyCache CRD. Reports the current state of the DependencyCache resource. */
public class DependencyCacheStatus {

  public enum State {
    PENDING,
    READY,
    FAILED,
    UPDATING
  }

  @JsonPropertyDescription("Current state of the DependencyCache")
  private State state = State.PENDING;

  @JsonPropertyDescription("Human-readable message describing the current state")
  private String message;

  @JsonPropertyDescription("Name of the created PVC (when successful)")
  private String createdPvcName;

  @JsonPropertyDescription("Timestamp of the last reconciliation")
  private String lastReconciled;

  @JsonPropertyDescription("Error message in case of failure")
  private String errorMessage;

  @JsonPropertyDescription("Generation observed by the controller")
  private Long observedGeneration;

  // Constructors
  public DependencyCacheStatus() {}

  public DependencyCacheStatus(State state, String message) {
    this.state = state;
    this.message = message;
  }

  // Getters and Setters
  public State getState() {
    return state;
  }

  public void setState(State state) {
    this.state = state;
  }

  public String getMessage() {
    return message;
  }

  public void setMessage(String message) {
    this.message = message;
  }

  public String getCreatedPvcName() {
    return createdPvcName;
  }

  public void setCreatedPvcName(String createdPvcName) {
    this.createdPvcName = createdPvcName;
  }

  public String getLastReconciled() {
    return lastReconciled;
  }

  public void setLastReconciled(String lastReconciled) {
    this.lastReconciled = lastReconciled;
  }

  public String getErrorMessage() {
    return errorMessage;
  }

  public void setErrorMessage(String errorMessage) {
    this.errorMessage = errorMessage;
  }

  public Long getObservedGeneration() {
    return observedGeneration;
  }

  public void setObservedGeneration(Long observedGeneration) {
    this.observedGeneration = observedGeneration;
  }

  @Override
  public String toString() {
    return "DependencyCacheStatus{"
        + "state="
        + state
        + ", message='"
        + message
        + '\''
        + ", createdPvcName='"
        + createdPvcName
        + '\''
        + ", lastReconciled='"
        + lastReconciled
        + '\''
        + ", errorMessage='"
        + errorMessage
        + '\''
        + ", observedGeneration="
        + observedGeneration
        + '}';
  }
}
