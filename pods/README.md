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

Use `shadok learn` for the complete operating workflow and build examples. The repository's application tests cover file publication and application responses; browser HMR requires a browser-level check. The [Quarkus live test](../docs/QUARKUS_LIVE_VALIDATION.md) verifies its production-image and framework-resource setup.

A demo should keep its source, application build configuration, runtime image, tests and usage guide together. Application images must provide the selected reload tool and command. The platform Deployment owns secrets, environment, resource settings and image pull credentials; the session selects the container and mounted directories.

## Example ownership

Run each example's commands from its own directory. Each example owns its build manifest, runtime image, synchronization configuration and guide. Shadok's Go operator and release CI do not depend on a root Gradle or Maven build.

| Example | Local entry point | Sync entry point |
| --- | --- | --- |
| Node | `npm ci` then `npm test` | `npm run dev:cluster` |
| Python | `./start.sh install` then `./start.sh test` | `shadok watch --config shadok.yaml --group python-source` |
| TypeScript | `npm ci` then `npm run build` | `npm run build:cluster` |
| Vite | `npm ci` then `npm run dev` | `npm run dev:cluster` |
| Spring | `mvn verify` | `mvn -Pshadok verify` |
| Quarkus | `./gradlew test` | `./gradlew shadokPublish` |

Each sample owns its build tooling and `shadok.yaml`. Run commands from the sample directory. For Quarkus, use `cd pods/quarkus-hello` and `./gradlew <task>`. Configure a destination and activate the session before running sync commands.

## Before synchronizing an example

Install the released CLI using the [installation guide](../docs/INSTALL_RELEASE.md), then configure a personal destination with `shadok docs configure`. For example, save this outside the repository as `~/.config/shadok/destinations.yaml` (replace every example value):

```yaml
version: 1
destinations:
  my-dev:
    url: https://sync.example.com
    namespace: team-a
    deployment: orders
    # caFile: /absolute/path/to/your-platform-ca.crt
```

```sh
export SHADOK_DESTINATION=my-dev
```

Select the appropriate Deployment for the example; a destination is not an instruction to deploy or replace some other application. The platform must already have installed the operator, deployed the application's baseline image and enabled its DevelopmentSession. The image must provide the live command and directories described in the example guide. Keep the gateway behind your platform's access boundary. Local application run/test commands need none of these cluster resources.

A sync ACK proves file application. Verify the example's HTTP response separately. When finished, stop its source watcher (`shadok unwatch --config shadok.yaml --group <group>`) or retained publication job, then disable the session and wait for baseline restoration. `shadok daemon stop` alone preserves jobs for its next start.

See the [complete gateway networking guide](../operator-go/internal/guidance/topics/network.md) for platform exposure, daemon destination settings and diagnostics. Run `shadok learn network` to read it in the CLI.
