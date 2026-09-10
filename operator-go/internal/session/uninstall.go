package session

import (
	"context"
	"fmt"
	api "shadok.org/operator/api/v1alpha1"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// CheckUninstall refuses to remove the controller while a session needs it.
func CheckUninstall(ctx context.Context, reader client.Reader, namespaces []string) error {
	if len(namespaces) == 0 {
		namespaces = []string{""}
	}
	for _, ns := range namespaces {
		sessions := &api.DevelopmentSessionList{}
		if err := reader.List(ctx, sessions, client.InNamespace(ns)); err != nil {
			return err
		}
		for _, s := range sessions.Items {
			if s.Spec.Enabled {
				return fmt.Errorf("disable session %s/%s and wait for baseline restoration before uninstall", s.Namespace, s.Name)
			}
			for _, f := range s.Finalizers {
				if f == finalizer {
					return fmt.Errorf("session %s/%s is still restoring its baseline", s.Namespace, s.Name)
				}
			}
		}
	}
	return nil
}
