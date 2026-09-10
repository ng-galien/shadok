# Application examples

These applications demonstrate language-specific build and reload commands. Shadok itself uses the same generic session and file synchronization contract for every application.

| Example | Workflow |
| --- | --- |
| [Node](node-hello/README.md) | Express source with nodemon and npm hooks |
| [Python](python-hello/README.md) | FastAPI with uvicorn source reload and pytest |
| [TypeScript](ts-hello/README.md) | Compile to `dist`, then publish successful output |
| [Vite](vite-hello/README.md) | Serve frontend sources in development mode |
| [Spring](spring-hello/README.md) | Compile JVM classes, publish through Maven, reload with DevTools |
| [Quarkus](quarkus-hello/README.md) | JVM application and Gradle build hook |

Use `shadok learn` for the complete operating workflow and build examples. The repository's application tests cover file publication and application responses; browser HMR and remote Quarkus dev mode require separate verification.

A demo should keep its source, application build configuration, runtime image, tests and usage guide together. Application images must provide the selected reload tool and command. The platform Deployment owns secrets, environment, resource settings and image pull credentials; the session selects the container and mounted directories.
