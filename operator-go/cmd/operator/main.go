package main

import (
	"context"
	"flag"
	"fmt"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"os"
	api "shadok.org/operator/api/v1alpha1"
	"shadok.org/operator/internal/buildinfo"
	"shadok.org/operator/internal/session"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metrics "sigs.k8s.io/controller-runtime/pkg/metrics/server"
	"strings"
)

func main() {
	image := flag.String("tool-image", "shadok-tools:local", "Seed and receiver image")
	showVersion := flag.Bool("version", false, "print version")
	leader := flag.Bool("leader-elect", true, "Enable leader election")
	leaderID := flag.String("leader-election-id", "shadok-operator", "Lease name")
	leaderNamespace := flag.String("leader-election-namespace", "", "Lease namespace")
	namespaces := flag.String("watch-namespaces", "", "Comma-separated namespaces; empty watches all")
	metricsAddress := flag.String("metrics-bind-address", "0", "Metrics bind address or 0 to disable")
	checkUninstall := flag.Bool("check-uninstall", false, "Fail if managed sessions still need the operator")
	flag.Parse()
	if *showVersion {
		fmt.Println(buildinfo.Version)
		return
	}
	ctrl.SetLogger(zap.New())
	s := runtime.NewScheme()
	must(corev1.AddToScheme(s))
	must(appsv1.AddToScheme(s))
	must(api.AddToScheme(s))
	if *checkUninstall {
		c, err := client.New(ctrl.GetConfigOrDie(), client.Options{Scheme: s})
		must(err)
		var scopes []string
		if *namespaces != "" {
			scopes = strings.Split(*namespaces, ",")
		}
		must(session.CheckUninstall(context.Background(), c, scopes))
		return
	}
	options := ctrl.Options{Scheme: s, Metrics: metrics.Options{BindAddress: *metricsAddress}, HealthProbeBindAddress: ":9000", LeaderElection: *leader, LeaderElectionID: *leaderID, LeaderElectionNamespace: *leaderNamespace, LeaderElectionReleaseOnCancel: true}
	if *namespaces != "" {
		options.Cache.DefaultNamespaces = map[string]cache.Config{}
		for _, ns := range strings.Split(*namespaces, ",") {
			options.Cache.DefaultNamespaces[strings.TrimSpace(ns)] = cache.Config{}
		}
	}
	m, err := ctrl.NewManager(ctrl.GetConfigOrDie(), options)
	must(err)
	must((&session.Reconciler{Client: m.GetClient(), ToolImage: *image}).SetupWithManager(m))
	must(m.AddHealthzCheck("ping", healthz.Ping))
	must(m.AddReadyzCheck("ping", healthz.Ping))
	ctx := ctrl.SetupSignalHandler()
	recoveryClient, err := client.New(ctrl.GetConfigOrDie(), client.Options{Scheme: s})
	must(err)
	var recoveryNamespaces []string
	if *namespaces != "" {
		recoveryNamespaces = strings.Split(*namespaces, ",")
	}
	go session.RunRecovery(ctx, recoveryClient, recoveryNamespaces)
	must(m.Start(ctx))
}
func must(err error) {
	if err != nil {
		ctrl.Log.Error(err, "operator failed")
		os.Exit(1)
	}
}
