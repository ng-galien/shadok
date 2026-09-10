package session

import (
	"context"
	"encoding/json"
	"fmt"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"reflect"
	api "shadok.org/operator/api/v1alpha1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"time"
)

const finalizer = "shadok.org/restore-baseline"
const liveAnnotation = "shadok.org/live-session"

type Reconciler struct {
	client.Client
	ToolImage string
}

func (r *Reconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	s := &api.DevelopmentSession{}
	if err := r.Get(ctx, req.NamespacedName, s); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}
	if !s.DeletionTimestamp.IsZero() {
		if controllerutil.ContainsFinalizer(s, finalizer) {
			if err := r.restore(ctx, s); err != nil {
				return ctrl.Result{}, err
			}
			controllerutil.RemoveFinalizer(s, finalizer)
			return ctrl.Result{}, r.Update(ctx, s)
		}
		return ctrl.Result{}, nil
	}
	if s.Spec.Enabled && !controllerutil.ContainsFinalizer(s, finalizer) {
		controllerutil.AddFinalizer(s, finalizer)
		return ctrl.Result{}, r.Update(ctx, s)
	}
	before := s.DeepCopy()
	var err error
	if s.Spec.Enabled {
		err = r.enable(ctx, s)
	} else {
		err = r.restore(ctx, s)
	}
	cond := metav1.Condition{Type: "Ready", ObservedGeneration: s.Generation, Status: metav1.ConditionTrue, Reason: "Baseline", Message: "Baseline template restored; Deployment owns its rollout"}
	if s.Spec.Enabled {
		cond.Reason = "LiveTemplateApplied"
		cond.Message = "Live template applied; rollout, synchronization and application reload are separate"
	}
	if err != nil {
		cond.Status = metav1.ConditionFalse
		cond.Reason = "ConflictOrUnavailable"
		cond.Message = err.Error()
	}
	meta.SetStatusCondition(&s.Status.Conditions, cond)
	s.Status.ObservedGeneration = s.Generation
	if e := r.Status().Patch(ctx, s, client.MergeFrom(before)); e != nil {
		return ctrl.Result{}, e
	}
	if err == nil && !s.Spec.Enabled && controllerutil.ContainsFinalizer(s, finalizer) {
		controllerutil.RemoveFinalizer(s, finalizer)
		return ctrl.Result{}, r.Update(ctx, s)
	}
	if err != nil {
		ctrl.LoggerFrom(ctx).Error(err, "session transition failed")
	}
	return ctrl.Result{RequeueAfter: 3 * time.Second}, nil
}
func (r *Reconciler) deployment(ctx context.Context, s *api.DevelopmentSession) (*appsv1.Deployment, error) {
	d := &appsv1.Deployment{}
	err := r.Get(ctx, client.ObjectKey{Namespace: s.Namespace, Name: s.Spec.Deployment}, d)
	return d, err
}
func baselineName(s *api.DevelopmentSession) string { return string(s.UID) + "-baseline" }
func (r *Reconciler) baseline(ctx context.Context, s *api.DevelopmentSession) (*corev1.ConfigMap, error) {
	cm := &corev1.ConfigMap{}
	err := r.Get(ctx, client.ObjectKey{Namespace: s.Namespace, Name: baselineName(s)}, cm)
	if err == nil {
		owner := metav1.GetControllerOf(cm)
		if owner == nil || owner.UID != s.UID {
			return nil, fmt.Errorf("baseline ownership conflict")
		}
	}
	return cm, err
}
func (r *Reconciler) enable(ctx context.Context, s *api.DevelopmentSession) error {
	d, err := r.deployment(ctx, s)
	if err != nil {
		return err
	}
	others := &api.DevelopmentSessionList{}
	if err = r.List(ctx, others, client.InNamespace(s.Namespace)); err != nil {
		return err
	}
	for _, other := range others.Items {
		if other.UID != s.UID && other.Spec.Deployment == s.Spec.Deployment && other.Spec.Enabled {
			return fmt.Errorf("another enabled session targets this Deployment")
		}
	}
	cm, err := r.baseline(ctx, s)
	if apierrors.IsNotFound(err) {
		if d.Spec.Template.Annotations[liveAnnotation] != "" {
			return fmt.Errorf("Deployment already live without this baseline")
		}
		raw, _ := json.Marshal(d.Spec.Template)
		cm = &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: baselineName(s), Namespace: s.Namespace}, Data: map[string]string{"template": string(raw), "deploymentUID": string(d.UID)}}
		if err = controllerutil.SetControllerReference(s, cm, r.Scheme()); err != nil {
			return err
		}
		if err = r.Create(ctx, cm); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	if cm.Data["deploymentUID"] != string(d.UID) {
		return fmt.Errorf("Deployment was replaced; refusing stale baseline")
	}
	var baseline corev1.PodTemplateSpec
	if err = json.Unmarshal([]byte(cm.Data["template"]), &baseline); err != nil {
		return err
	}
	generation := fmt.Sprint(s.Generation)
	if d.Spec.Template.Annotations[liveAnnotation] == string(s.UID) {
		if err = checkApplied(cm, d); err != nil {
			return err
		}
	}
	if d.Spec.Template.Annotations[liveAnnotation] == string(s.UID) && d.Spec.Template.Annotations["shadok.org/live-generation"] == generation {
		return nil
	}
	if owner := d.Spec.Template.Annotations[liveAnnotation]; owner != "" && owner != string(s.UID) {
		return fmt.Errorf("Deployment is owned by another live session")
	}
	if d.Spec.Template.Annotations[liveAnnotation] == "" && !reflect.DeepEqual(d.Spec.Template, baseline) {
		return fmt.Errorf("Deployment template changed outside Shadok; disable/reconfigure before reactivation")
	}
	source := d.DeepCopy()
	source.Spec.Template = baseline
	plan, err := Plan(s, source, r.ToolImage)
	if err != nil {
		return err
	}
	plan.Annotations[liveAnnotation] = string(s.UID)
	plan.Annotations["shadok.org/live-generation"] = generation
	before := d.DeepCopy()
	d.Spec.Template = corev1.PodTemplateSpec{ObjectMeta: metav1.ObjectMeta{Labels: plan.Labels, Annotations: plan.Annotations}, Spec: plan.Spec}
	// Persist the server-defaulted intent before mutating the Deployment. An
	// interruption after the patch can then recover without losing the baseline.
	dryRun := d.DeepCopy()
	if err = r.Patch(ctx, dryRun, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{}), client.DryRunAll); err != nil {
		return err
	}
	pending, _ := json.Marshal(dryRun.Spec.Template)
	cm.Data["pendingTemplate"] = string(pending)
	if err = r.Update(ctx, cm); err != nil {
		return err
	}
	if err = r.Patch(ctx, d, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{})); err != nil {
		return err
	}
	raw, _ := json.Marshal(d.Spec.Template)
	cm.Data["appliedTemplate"] = string(raw)
	delete(cm.Data, "pendingTemplate")
	if err = r.Update(ctx, cm); err != nil {
		return err
	}
	for _, c := range baseline.Spec.Containers {
		if c.Name == s.Spec.Container {
			s.Status.BaselineImage = c.Image
		}
	}
	return nil
}
func (r *Reconciler) restore(ctx context.Context, s *api.DevelopmentSession) error {
	cm, err := r.baseline(ctx, s)
	if apierrors.IsNotFound(err) {
		d, readErr := r.deployment(ctx, s)
		if readErr != nil {
			return client.IgnoreNotFound(readErr)
		}
		if d.Spec.Template.Annotations[liveAnnotation] == string(s.UID) {
			return fmt.Errorf("live Deployment has no saved baseline; cannot restore")
		}
		return nil
	}
	if err != nil {
		return err
	}
	d, err := r.deployment(ctx, s)
	if apierrors.IsNotFound(err) {
		return r.Delete(ctx, cm)
	}
	if err != nil {
		return err
	}
	if cm.Data["deploymentUID"] != string(d.UID) {
		return fmt.Errorf("Deployment UID changed; baseline restoration requires reconciliation")
	}
	var original corev1.PodTemplateSpec
	if err = json.Unmarshal([]byte(cm.Data["template"]), &original); err != nil {
		return err
	}
	if d.Spec.Template.Annotations[liveAnnotation] == string(s.UID) {
		if err = checkApplied(cm, d); err != nil {
			return err
		}
		before := d.DeepCopy()
		d.Spec.Template = original
		if err = r.Patch(ctx, d, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{})); err != nil {
			return err
		}
	} else if !reflect.DeepEqual(d.Spec.Template, original) {
		return fmt.Errorf("external template change: refusing to overwrite with saved baseline")
	}
	return client.IgnoreNotFound(r.Delete(ctx, cm))
}
func (r *Reconciler) SetupWithManager(m ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(m).For(&api.DevelopmentSession{}).Owns(&corev1.ConfigMap{}).Complete(r)
}

func checkApplied(cm *corev1.ConfigMap, d *appsv1.Deployment) error {
	for _, key := range []string{"appliedTemplate", "pendingTemplate"} {
		if cm.Data[key] == "" {
			continue
		}
		var expected corev1.PodTemplateSpec
		if err := json.Unmarshal([]byte(cm.Data[key]), &expected); err != nil {
			return err
		}
		if reflect.DeepEqual(expected, d.Spec.Template) {
			return nil
		}
	}
	return fmt.Errorf("live template differs from recorded intent; refusing to overwrite external changes")
}
