package org.shadok.operator.model;

/**
 * Enum representing the supported application types. This is used by the Application CRD to specify
 * the type of application.
 */
public enum ApplicationType {
  SPRING,
  QUARKUS,
  NODE,
  PYTHON,
  GO,
  RUBY,
  PHP,
  DOTNET,
  OTHER;
}
