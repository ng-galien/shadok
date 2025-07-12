package org.shadok.operator.model.code;

import com.fasterxml.jackson.annotation.JsonPropertyDescription;

/**
 * Status for ProjectSource CRD.
 * Reports the current state of the ProjectSource resource.
 */
public class ProjectSourceStatus {

    public enum State {
        PENDING,
        READY,
        FAILED,
        UPDATING
    }

    @JsonPropertyDescription("Current state of the ProjectSource")
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
    public ProjectSourceStatus() {}

    public ProjectSourceStatus(State state, String message) {
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
        return "ProjectSourceStatus{" +
                "state=" + state +
                ", message='" + message + '\'' +
                ", createdPvcName='" + createdPvcName + '\'' +
                ", lastReconciled='" + lastReconciled + '\'' +
                ", errorMessage='" + errorMessage + '\'' +
                ", observedGeneration=" + observedGeneration +
                '}';
    }
}
