# Vite live development

From this directory, run `npm ci`, then build the supplied Dockerfile. Configure a DevelopmentSession for the existing Deployment with container `app`, directory name `application`, imagePath and mountPath `/app/src`, UID/GID 1000, workingDir `/app`, command `./node_modules/.bin/vite` and args `[--host, 0.0.0.0, --port, "8080"]`.

After activating the session and configuring the gateway destination:

```sh
npm run dev:cluster
```

The source group in `shadok.yaml` watches `src`. It does not synchronize `index.html`, package files or dependencies; change the configured roots/image if those need updating. Edit `src/main.js` and inspect the application through its usual route. `npm run build` produces a production bundle, which this source-watch configuration does not publish.

Vite's development server supplies reload/HMR. Browser HMR additionally requires a reachable WebSocket route and suitable Vite host configuration for your ingress. The automated Shadok test verifies updated source delivery, not browser HMR.

See [release installation](../../docs/INSTALL_RELEASE.md), [session configuration](../../operator-go/internal/guidance/topics/configure.md) and [build hooks](../../operator-go/internal/guidance/topics/builds.md). The platform provides the Deployment; Shadok does not create its application dependencies.
