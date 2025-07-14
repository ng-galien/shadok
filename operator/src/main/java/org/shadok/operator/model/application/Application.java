package org.shadok.operator.model.application;

import io.fabric8.kubernetes.api.model.Namespaced;
import io.fabric8.kubernetes.client.CustomResource;
import io.fabric8.kubernetes.model.annotation.Group;
import io.fabric8.kubernetes.model.annotation.Kind;
import io.fabric8.kubernetes.model.annotation.Version;

/**
 * Application Custom Resource Definition.
 *
 * <p>This is a parent CRD that groups ProjectSource and DependencyCache CRDs and adds an
 * application type (Spring, Quarkus, Node, Python, etc.).
 *
 * <p>Example usage:
 *
 * <pre>
 * apiVersion: shadok.org/v1
 * kind: Application
 * metadata:
 *   name: my-application
 *   namespace: default
 * spec:
 *   applicationType: QUARKUS
 *   projectSourceName: "my-project-source"
 *   dependencyCacheName: "maven-cache"
 * </pre>
 */
@Group("shadok.org")
@Version("v1")
@Kind("Application")
public class Application extends CustomResource<ApplicationSpec, ApplicationStatus>
    implements Namespaced {

  /** Default constructor required for deserialization. */
  public Application() {
    super();
  }
}
