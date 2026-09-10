# Build integrations

Use `mode: watch` for editable source files, and `mode: build` for completed compiler outputs. Shadok transfers files; the application's image and command must provide the corresponding reload behavior. It does not install language dependencies or rebuild container images.

For TypeScript output in dist, configure:

```yaml
version: 1
project: orders
groups:
  service:
    mode: build
    roots:
      - mount: application
        path: dist
```

Map the session's application directory to the runtime's output directory, for example imagePath/mountPath /app/dist, and use the application's actual development command. A package.json can contain:

```json
{"scripts":{"build":"tsc","build:cluster":"shadok build --config shadok.yaml --group service -- npm run build"}}
```

`shadok build` runs the command in the current working directory, holds a cooperative project build lock and captures a snapshot after success. Failed builds publish nothing. `shadok publish --config shadok.yaml --group service` is appropriate in a successful build hook: it captures completed outputs and waits for that revision's ACK. Hook-only workflows must prevent concurrent writers of the same output directories. All CLI flags must precede `--`, then the build command and its arguments follow. Put the same shadok executable on the PATH used by the build tool.

For Node source, use the source group from `shadok docs configure` and an npm script `"dev:cluster": "shadok watch --config shadok.yaml --group source"`. For Python, use a watch group rooted at your source directory and configure an image/start command with a real file reload mechanism (for example the application's existing development server). Plain Python execution does not acquire automatic reload simply because files change. Vite similarly needs its dev server running in the application image; verify browser HMR separately from file delivery.

For Maven/Spring, map target/classes to a directory included in the JVM classpath. Use an image with required libraries and Spring DevTools, a JVM classpath/start command and readiness probe that match that image. Example project group:

```yaml
version: 1
project: service
groups:
  service:
    mode: build
    roots:
      - mount: classes
        path: target/classes
```

The simplest wrapper is `shadok build --group service -- mvn verify`. For a successful Maven lifecycle hook, add this optional profile to the POM and run `mvn -Pshadok verify`:

```xml
<profile>
  <id>shadok</id>
  <build><plugins><plugin>
    <groupId>org.codehaus.mojo</groupId><artifactId>exec-maven-plugin</artifactId><version>3.6.3</version>
    <inherited>false</inherited>
    <executions><execution><id>publish-live</id><phase>verify</phase><goals><goal>exec</goal></goals>
      <configuration><executable>shadok</executable><arguments>
        <argument>publish</argument><argument>--config</argument><argument>${project.basedir}/shadok.yaml</argument>
        <argument>--group</argument><argument>service</argument>
      </arguments></configuration>
    </execution></executions>
  </plugin></plugins></build>
</profile>
```

Place that profile inside `<profiles>`; do not combine it with a wrapper that would publish twice. For multi-module builds, select the module containing the actual runtime outputs. Dependency changes require a compatible image/dependency update, not merely transferring classes.

Gradle Kotlin DSL for a Java project's completed classes/resources:

```kotlin
tasks.register<Exec>("shadokPublish") {
    dependsOn(tasks.named("classes"), tasks.named("test"))
    workingDir(project.projectDir)
    commandLine("shadok", "publish", "--config",
        project.file("shadok.yaml").absolutePath, "--group", "service")
}
```

Configure separate roots for build/classes/java/main and build/resources/main if both exist, with matching session directory names and classpath entries. Run `./gradlew shadokPublish`; failed dependencies prevent publication. Alternatively wrap the successful build with `shadok build --group service -- ./gradlew build`. This hook proves publication, not a framework-specific remote restart; verify the application's actual response.
