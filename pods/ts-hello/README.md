# TypeScript live development

## Run locally

From `pods/ts-hello`, with Node.js 20+ and npm.

```sh
npm ci
npm run build
npm start
```

Open http://localhost:8080/hello. Stop the server with Ctrl+C.

## Run with Shadok

Follow the [shared session and destination setup](../README.md#before-synchronizing-an-example). The commands below also run from this example directory.

From this directory, run `npm ci` and `npm run build`, then build the supplied Dockerfile for the platform's baseline Deployment.

Configure a DevelopmentSession with container `app`, directory name `application`, imagePath and mountPath `/app/dist`, UID/GID 1000, workingDir `/app`, command `node` and args `[--watch, dist/server.js]`. The application image must include Node and the initial compiled output.

After activating the session and configuring the gateway destination:

```sh
npm run build:cluster
```

This compiles and then publishes the `dist` build group declared in `shadok.yaml`. A compiler failure prevents publication. Change the response in `src/server.ts`, build again, and verify `/hello` through the application's normal route. Node handles restart when the compiled files change.

See [release installation](../../docs/INSTALL_RELEASE.md), [session configuration](../../operator-go/internal/guidance/topics/configure.md) and [build hooks](../../operator-go/internal/guidance/topics/builds.md). The platform provides the Deployment; Shadok does not create its application dependencies.
