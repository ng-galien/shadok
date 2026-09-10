# Node application example

Express serves a greeting and health endpoints. `Dockerfile.dev` includes nodemon for source reload. Use this supplied image layout for the development session.

From this directory:

```sh
npm ci
npm test
npm run dev
```

Read `package.json` for available scripts and `shadok learn` for synchronization setup. The repository's shared `shadok.yaml` defines source groups; personal gateway destinations belong in the user's destination configuration. Use a watch group for source files. Build hooks must publish only after successful completion.

Endpoints include `/`, `/hello`, `/hello/json`, `/health` and `/ready`. Local defaults use port 3000. Kubernetes resources and the application image belong to the platform; configure a `DevelopmentSession` with the actual application Deployment/container names and source paths.
