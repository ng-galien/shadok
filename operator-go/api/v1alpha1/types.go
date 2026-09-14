// Package v1alpha1 defines the experimental generic development session API.
// +kubebuilder:object:generate=true
// +groupName=shadok.org
package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/scheme"
)

var GroupVersion = schema.GroupVersion{Group: "shadok.org", Version: "v1alpha1"}
var SchemeBuilder = &scheme.Builder{GroupVersion: GroupVersion}
var AddToScheme = SchemeBuilder.AddToScheme

type Directory struct {
	// +kubebuilder:validation:Pattern=`^[a-z][a-z0-9-]*$`
	// +kubebuilder:validation:MaxLength=51
	Name string `json:"name"`
	// Omit to start with an empty working directory; otherwise copy from the application image.
	ImagePath string `json:"imagePath,omitempty"`
	MountPath string `json:"mountPath"`
	// Build output/source directory relative to the CLI working directory. Omit for non-synchronized volumes.
	LocalPath string   `json:"localPath,omitempty"`
	Exclude   []string `json:"exclude,omitempty"`
}
type Start struct {
	// +kubebuilder:validation:MinItems=1
	Command    []string `json:"command"`
	Args       []string `json:"args,omitempty"`
	WorkingDir string   `json:"workingDir,omitempty"`
}

// ToolFile is downloaded and verified before the application starts.
type ToolFile struct {
	// +kubebuilder:validation:Pattern=`^[A-Za-z0-9][A-Za-z0-9._-]*$`
	Path string `json:"path"`
	// +kubebuilder:validation:Pattern=`^https://`
	URL string `json:"url"`
	// +kubebuilder:validation:Pattern=`^[a-f0-9]{64}$`
	SHA256 string `json:"sha256"`
}

// SessionVolume exists only while live mode is enabled. Files use a per-pod emptyDir.
// +kubebuilder:validation:XValidation:rule="(has(self.persistentVolumeClaim) ? 1 : 0) + (has(self.configMap) ? 1 : 0) + (has(self.secret) ? 1 : 0) + (has(self.files) && size(self.files) > 0 ? 1 : 0) == 1",message="choose exactly one volume source"
type SessionVolume struct {
	// +kubebuilder:validation:Pattern=`^[a-z][a-z0-9-]*$`
	// +kubebuilder:validation:MaxLength=49
	Name                  string                                    `json:"name"`
	MountPath             string                                    `json:"mountPath"`
	ReadOnly              bool                                      `json:"readOnly,omitempty"`
	PersistentVolumeClaim *corev1.PersistentVolumeClaimVolumeSource `json:"persistentVolumeClaim,omitempty"`
	ConfigMap             *corev1.ConfigMapVolumeSource             `json:"configMap,omitempty"`
	Secret                *corev1.SecretVolumeSource                `json:"secret,omitempty"`
	// +listType=map
	// +listMapKey=path
	Files []ToolFile `json:"files,omitempty"`
}

// InitStep runs after image directories are seeded and before the application starts.
// All declared live directories are mounted at their application mount paths.
type InitStep struct {
	// +kubebuilder:validation:Pattern=`^[a-z][a-z0-9-]*$`
	// +kubebuilder:validation:MaxLength=51
	Name string `json:"name"`
	// +kubebuilder:validation:MinLength=1
	Image string `json:"image"`
	// +kubebuilder:validation:Enum=Always;IfNotPresent;Never
	ImagePullPolicy string `json:"imagePullPolicy,omitempty"`
	// +kubebuilder:validation:MinItems=1
	Command    []string `json:"command"`
	Args       []string `json:"args,omitempty"`
	WorkingDir string   `json:"workingDir,omitempty"`
}

type SessionSpec struct {
	// Enable live transformation of the existing Deployment; false restores its baseline.
	Enabled bool `json:"enabled"`

	// Deployment in the same namespace, transformed in place.
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="deployment is immutable; create a new session to retarget"
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=253
	Deployment string `json:"deployment"`
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=63
	Container string `json:"container"`
	// Optional live image; the baseline image is restored when disabled.
	Image string `json:"image,omitempty"`
	// +kubebuilder:validation:Enum=Always;IfNotPresent;Never
	ImagePullPolicy string `json:"imagePullPolicy,omitempty"`
	// +kubebuilder:validation:MinItems=1
	// +listType=map
	// +listMapKey=name
	Directories []Directory `json:"directories"`
	Start       Start       `json:"start"`
	// Ordered initialization commands; no framework-specific behavior is inferred.
	// +listType=atomic
	Init []InitStep `json:"init,omitempty"`
	// Additional application mounts, managed and removed by the operator.
	// +listType=map
	// +listMapKey=name
	Volumes []SessionVolume `json:"volumes,omitempty"`
	// A session-specific UID/GID for shared emptyDir writes. Must match the baseline runtime.
	// +kubebuilder:validation:Minimum=1
	RunAsUser int64 `json:"runAsUser"`
	// +kubebuilder:validation:Minimum=1
	RunAsGroup int64 `json:"runAsGroup"`
}
type SessionStatus struct {
	BaselineImage      string             `json:"baselineImage,omitempty"`
	ObservedGeneration int64              `json:"observedGeneration,omitempty"`
	Conditions         []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
type DevelopmentSession struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              SessionSpec   `json:"spec"`
	Status            SessionStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true
type DevelopmentSessionList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []DevelopmentSession `json:"items"`
}

func init() { SchemeBuilder.Register(&DevelopmentSession{}, &DevelopmentSessionList{}) }
