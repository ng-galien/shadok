package org.shadok.operator.model.code;

import io.fabric8.kubernetes.api.model.Namespaced;
import io.fabric8.kubernetes.client.CustomResource;
import io.fabric8.kubernetes.model.annotation.Group;
import io.fabric8.kubernetes.model.annotation.Kind;
import io.fabric8.kubernetes.model.annotation.Version;

/**
 * ProjectSource Custom Resource Definition.
 * 
 * This CRD allows creating a PVC from an existing PV with a specific path
 * to mount project sources for live development in Kubernetes.
 * 
 * Example usage:
 * <pre>
 * apiVersion: shadok.com/v1
 * kind: ProjectSource
 * metadata:
 *   name: my-project-source
 *   namespace: default
 * spec:
 *   persistentVolumeName: "dev-sources-pv"
 *   sourcePath: "/sources/my-app"
 *   pvcName: "my-app-sources"
 *   storageSize: "2Gi"
 * </pre>
 */
@Group("shadok.org")
@Version("v1")
@Kind("ProjectSource")
public class ProjectSource extends CustomResource<ProjectSourceSpec, ProjectSourceStatus>
        implements Namespaced {

    /**
     * Default constructor required for deserialization.
     */
    public ProjectSource() {
        super();
    }


}
