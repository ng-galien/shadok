# Node application example

Express serves a greeting and health endpoints. `Dockerfile.dev` includes nodemon for source reload. Use this supplied image layout for the development session.

From `pods/node-hello`, with Node.js 20+ and npm:

```sh
npm ci
npm test
npm run dev
```

Read `package.json` for available scripts and `shadok learn` for synchronization setup. This example's `shadok.yaml` defines the `node-source` group; personal gateway destinations belong in the user's destination configuration. Use a watch group for source files. Build hooks must publish only after successful completion.

Endpoints include `/`, `/hello`, `/hello/json`, `/health` and `/ready`. Local defaults use port 3000. Kubernetes resources and the application image belong to the platform; configure a `DevelopmentSession` with the actual application Deployment/container names and source paths.

## Run with Shadok

Follow the [shared session and destination setup](../README.md#before-synchronizing-an-example). Build the supplied image with `docker build -f Dockerfile.dev -t node-hello:dev .` from this example directory and let the platform deploy it. Configure mount `application` with imagePath/mountPath `/app/src`, workingDir `/app`, UID/GID 1000, command `./node_modules/.bin/nodemon` and args `[--legacy-watch, src/app.js]`.

Run `npm run dev:cluster` to test and start watching, `npm run cluster:status` to inspect synchronization, and `npm run cluster:stop` to stop watching. Verify `/hello` through the application's existing Service/Ingress after a source change. Stop any local server with Ctrl+C.
