# Reload verification reference

The runtime guides include these checks in their activation chapter. Use this checklist to record evidence for the actual application being configured.

## 1. Establish the baseline

Record the image digest, command, application URL and HTTP response. Retain the rendered Deployment locally if permitted. Have the platform collect this information when your rights cover only DevelopmentSessions.

## 2. Confirm live startup

Check the session's Ready condition refers to its current generation, then call the application's URL. Check runtime logs for the intended reload mechanism. Readiness of the Shadok receiver is not proof that the application has loaded the new code.

## 3. Exercise the application

| Operation | Evidence |
| --- | --- |
| Modify an existing response | HTTP returns the new value |
| Add an endpoint method | 404 becomes the expected successful response |
| Add a class/module and register its route | New endpoint responds |
| Remove the class/module and registration; clean-build if compiled | Endpoint returns 404; unchanged route still works |

Publish only successful builds. For source watching, wait for the selected watcher. An ACK establishes file application, not framework behavior. Check browser HMR in the browser when that is the required behavior.

## 4. Confirm no Kubernetes restart

Using the target context, namespace and actual Deployment selector:

```sh
kubectl --context "$CONTEXT" -n "$NAMESPACE" get pods -l app=YOUR_APP_LABEL \
  -o jsonpath='{range .items[*]}{.metadata.uid}{" "}{range .status.containerStatuses[*]}{.name}{" "}{.containerID}{" "}{.restartCount}{"\n"}{end}{end}'
```

Capture before and after updates. Compare the application container, not just the receiver: Pod UID, container ID and restart count must remain unchanged. The framework's application process/context may restart internally.

## 5. Restore and record

Stop the project's synchronization job and disable its DevelopmentSession using the runtime guide's commands. Check the Baseline condition for the current generation, the original HTTP response and restored startup configuration.

Record the exact runtime version, production image digest, paths, live command and observations. Do not generalize a validated layout to uninspected production images.
