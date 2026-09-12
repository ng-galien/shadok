package session

import (
	"context"
	"encoding/json"
	"fmt"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/util/strategicpatch"
	api "shadok.org/operator/api/v1alpha1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"slices"
	"strings"
	"time"
)

const recoveryLabel = "shadok.org/recovery-session"

func markRecovery(cm *corev1.ConfigMap, s *api.DevelopmentSession) {
	if cm.Labels == nil {
		cm.Labels = map[string]string{}
	}
	cm.Labels[recoveryLabel] = string(s.UID)
	cm.OwnerReferences = nil // The record must survive session and CRD deletion.
	raw, _ := json.Marshal(s)
	cm.Data["session"] = string(raw)
}

func (r *Reconciler) persistRecovery(ctx context.Context, s *api.DevelopmentSession) error {
	cm, err := r.baseline(ctx, s)
	if apierrors.IsNotFound(err) {
		return nil
	}
	if err != nil {
		return err
	}
	markRecovery(cm, s)
	return r.Update(ctx, cm)
}

// Restore our changes while replaying external edits onto the original template.
func restoreTemplate(cm *corev1.ConfigMap, current, original corev1.PodTemplateSpec) (corev1.PodTemplateSpec, error) {
	applied := cm.Data["appliedTemplate"]
	if pending := cm.Data["pendingTemplate"]; pending != "" {
		var intended corev1.PodTemplateSpec
		if err := json.Unmarshal([]byte(pending), &intended); err != nil {
			return original, err
		}
		if applied == "" || intended.Annotations["shadok.org/live-generation"] == current.Annotations["shadok.org/live-generation"] {
			applied = pending
		}
	}
	if applied == "" {
		return original, fmt.Errorf("missing applied template; recovery record retained")
	}
	now, _ := json.Marshal(current)
	base, _ := json.Marshal(original)
	changes, err := strategicpatch.CreateTwoWayMergePatch([]byte(applied), now, corev1.PodTemplateSpec{})
	if err != nil {
		return original, err
	}
	restored, err := strategicpatch.StrategicMergePatch(base, changes, corev1.PodTemplateSpec{})
	if err != nil {
		return original, err
	}
	var result corev1.PodTemplateSpec
	err = json.Unmarshal(restored, &result)
	if err != nil {
		return result, err
	}
	// Reserved injected resources are removed even if edited externally.
	stripContainers := func(items []corev1.Container) []corev1.Container {
		items = slices.DeleteFunc(items, func(c corev1.Container) bool { return strings.HasPrefix(c.Name, "shadok-") })
		for i := range items {
			items[i].VolumeMounts = slices.DeleteFunc(items[i].VolumeMounts, func(v corev1.VolumeMount) bool { return strings.HasPrefix(v.Name, "shadok-") })
		}
		return items
	}
	result.Spec.Containers = stripContainers(result.Spec.Containers)
	result.Spec.InitContainers = stripContainers(result.Spec.InitContainers)
	result.Spec.Volumes = slices.DeleteFunc(result.Spec.Volumes, func(v corev1.Volume) bool { return strings.HasPrefix(v.Name, "shadok-") })
	return result, nil
}

// RecoverOrphans uses the core API for durable records, independently of CRD informers.
// Multiple replicas are safe: restoration uses optimistic locking and is idempotent.
func RecoverOrphans(ctx context.Context, c client.Client, namespaces []string) error {
	if len(namespaces) == 0 {
		namespaces = []string{""}
	}
	for _, ns := range namespaces {
		list := &corev1.ConfigMapList{}
		if err := c.List(ctx, list, client.InNamespace(strings.TrimSpace(ns)), client.HasLabels{recoveryLabel}); err != nil {
			return err
		}
		for i := range list.Items {
			cm := &list.Items[i]
			var saved api.DevelopmentSession
			if err := json.Unmarshal([]byte(cm.Data["session"]), &saved); err != nil {
				ctrl.LoggerFrom(ctx).Error(err, "invalid recovery record retained", "namespace", cm.Namespace, "configMap", cm.Name)
				continue
			}
			if saved.Namespace != cm.Namespace || baselineName(&saved) != cm.Name || string(saved.UID) != cm.Labels[recoveryLabel] {
				ctrl.LoggerFrom(ctx).Error(fmt.Errorf("recovery identity mismatch"), "invalid recovery record retained", "namespace", cm.Namespace, "configMap", cm.Name)
				continue
			}
			current := &api.DevelopmentSession{}
			err := c.Get(ctx, client.ObjectKeyFromObject(&saved), current)
			missing := apierrors.IsNotFound(err) || meta.IsNoMatchError(err)
			if err != nil && !missing {
				return err
			}
			if !missing && current.UID == saved.UID && current.DeletionTimestamp.IsZero() && current.Spec.Enabled {
				continue
			}
			if err := (&Reconciler{Client: c}).restore(ctx, &saved); err != nil {
				ctrl.LoggerFrom(ctx).Error(err, "session cleanup will retry", "namespace", saved.Namespace, "session", saved.Name)
			}
		}
	}
	return nil
}

func RunRecovery(ctx context.Context, c client.Client, namespaces []string) {
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()
	for {
		if err := RecoverOrphans(ctx, c, namespaces); err != nil {
			ctrl.LoggerFrom(ctx).Error(err, "recovery scan failed")
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
