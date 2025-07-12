package org.shadok.operator.model.cache;

import io.fabric8.kubernetes.api.model.Namespaced;
import io.fabric8.kubernetes.client.CustomResource;
import io.fabric8.kubernetes.model.annotation.Group;
import io.fabric8.kubernetes.model.annotation.Kind;
import io.fabric8.kubernetes.model.annotation.Version;

/**
 * DependencyCache Custom Resource Definition.
 * 
 * This CRD allows creating a PVC dedicated to caching dependencies (like Maven's m2 repository)
 * that can be shared between multiple applications.
 * 
 * Example usage:
 * <pre>
 * apiVersion: shadok.org/v1
 * kind: DependencyCache
 * metadata:
 *   name: maven-cache
 *   namespace: default
 * spec:
 *   persistentVolumeName: "dev-cache-pv"
 *   cachePath: "/cache/m2"
 *   pvcName: "maven-cache"
 *   storageSize: "5Gi"
 * </pre>
 */
@Group("shadok.org")
@Version("v1")
@Kind("DependencyCache")
public class DependencyCache extends CustomResource<DependencyCacheSpec, DependencyCacheStatus>
        implements Namespaced {

    /**
     * Default constructor required for deserialization.
     */
    public DependencyCache() {
        super();
    }

}