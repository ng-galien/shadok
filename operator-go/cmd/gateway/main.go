package main

import (
	"flag"
	"fmt"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"log"
	"net/http"
	api "shadok.org/operator/api/v1alpha1"
	"shadok.org/operator/internal/buildinfo"
	"shadok.org/operator/internal/gateway"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"strings"
	"time"
)

func main() {
	address := flag.String("listen", ":8080", "HTTP listen address; TLS terminated at Ingress")
	cert := flag.String("tls-cert", "", "optional TLS certificate")
	key := flag.String("tls-key", "", "TLS private key")
	showVersion := flag.Bool("version", false, "print version")
	namespaces := flag.String("watch-namespaces", "", "Comma-separated permitted namespaces; empty allows all")
	flag.Parse()
	if *showVersion {
		fmt.Println(buildinfo.Version)
		return
	}
	s := runtime.NewScheme()
	corev1.AddToScheme(s)
	api.AddToScheme(s)
	c, err := client.New(ctrl.GetConfigOrDie(), client.Options{Scheme: s})
	if err != nil {
		log.Fatal(err)
	}
	allowed := map[string]bool{}
	if *namespaces != "" {
		for _, ns := range strings.Split(*namespaces, ",") {
			allowed[strings.TrimSpace(ns)] = true
		}
	}
	server := &http.Server{Addr: *address, Handler: &gateway.Handler{Resolver: gateway.KubernetesResolver{Reader: c, Namespaces: allowed}}, ReadHeaderTimeout: 10 * time.Second}
	if *cert != "" {
		log.Fatal(server.ListenAndServeTLS(*cert, *key))
	}
	log.Fatal(server.ListenAndServe())
}
