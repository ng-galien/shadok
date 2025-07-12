package org.shadok.operator.model.application;

import com.fasterxml.jackson.annotation.JsonPropertyDescription;

/**
 * Status for Application CRD.
 * Reports the current state of the Application resource.
 */
public class ApplicationStatus {

    public enum State {
        PENDING,
        READY,
        FAILED,
        UPDATING
    }

    @JsonPropertyDescription("Current state of the Application")
    private State state = State.PENDING;

    @JsonPropertyDescription("Human-readable message describing the current state")
    private String message;

    @JsonPropertyDescription("Status of the referenced ProjectSource")
    private String projectSourceStatus;

    @JsonPropertyDescription("Status of the referenced DependencyCache")
    private String dependencyCacheStatus;

    @JsonPropertyDescription("Timestamp of the last reconciliation")
    private String lastReconciled;

    @JsonPropertyDescription("Error message in case of failure")
    private String errorMessage;

    @JsonPropertyDescription("Generation observed by the controller")
    private Long observedGeneration;

    // Constructors
    public ApplicationStatus() {}

    public ApplicationStatus(State state, String message) {
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

    public String getProjectSourceStatus() {
        return projectSourceStatus;
    }

    public void setProjectSourceStatus(String projectSourceStatus) {
        this.projectSourceStatus = projectSourceStatus;
    }

    public String getDependencyCacheStatus() {
        return dependencyCacheStatus;
    }

    public void setDependencyCacheStatus(String dependencyCacheStatus) {
        this.dependencyCacheStatus = dependencyCacheStatus;
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
        return "ApplicationStatus{" +
                "state=" + state +
                ", message='" + message + '\'' +
                ", projectSourceStatus='" + projectSourceStatus + '\'' +
                ", dependencyCacheStatus='" + dependencyCacheStatus + '\'' +
                ", lastReconciled='" + lastReconciled + '\'' +
                ", errorMessage='" + errorMessage + '\'' +
                ", observedGeneration=" + observedGeneration +
                '}';
    }
}