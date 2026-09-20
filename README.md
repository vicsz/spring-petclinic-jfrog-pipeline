# Spring Petclinic: Jenkins + JFrog Cloud

This repository demonstrates a Jenkins pipeline for Spring Petclinic. Jenkins
uses Gradle to resolve plugins and dependencies through JFrog Cloud, Docker
packages the verified JAR, and Jenkins smoke-tests the resulting image.

![Jenkins and JFrog dependency flow](assets/jfrog-pipeline-flow.png)

## Architecture

Jenkins is the pipeline orchestrator. It binds a JFrog credential, runs one
Gradle build, and then gives the tested JAR to Docker:

1. Jenkins checks out the repository.
2. Gradle resolves plugins and project dependencies from the JFrog
   `gradle-virtual` repository.
3. JFrog serves cached artifacts or proxies requests to its configured,
   approved upstream repositories.
4. Gradle runs the tests and creates the executable Spring Boot JAR.
5. Docker packages that exact JAR into a Java 17 runtime image.
6. Jenkins starts the image on an ephemeral port and performs an HTTP smoke
   test.

There is no second Gradle build inside Docker. This keeps dependency resolution
on the authenticated JFrog path and ensures that the image contains the same
artifact Jenkins tested.

## Pipeline files

- `Jenkinsfile` — checkout, authenticated Gradle build, test reporting, image
  packaging, and smoke test.
- `Dockerfile` — minimal runtime-only Java 17 image pinned by digest.
- `.dockerignore` — allows only the Dockerfile and built JAR into the build
  context.
- `build.gradle` and `settings.gradle` — JFrog-backed dependency and plugin
  resolution when the JFrog variables are supplied, with project-level
  repositories blocked.
- `gradle/verification-metadata.xml` — checked-in SHA-256 values for resolved
  plugins and dependencies.

## Jenkins setup

Create a Pipeline job from this repository's `main` branch and configure one
Jenkins username/password credential:

```text
Credential ID: jfrog-cloud-gradle
Username:      JFrog account username
Password:      JFrog identity token
```

The repository endpoint is public configuration and contains no secret:

```text
https://trialbf1216.jfrog.io/artifactory/gradle-virtual
```

Jenkins injects the username and token only while Gradle is running. It builds
with:

```bash
./gradlew clean build
```

The Gradle `build` lifecycle runs tests, formatting validation, Checkstyle, and
the NoHTTP policy before Jenkins packages the JAR. The pipeline publishes JUnit
results and validation reports, uses build-specific image/container names,
limits job concurrency and runtime, and prints container logs when the smoke
test fails. Successful builds archive the tested `petclinic.jar`, a loadable
Docker image archive, and its SHA-256 checksum. Jenkins keeps ten build records
and the artifacts from the latest three builds.

## Build and run locally

Requirements: Java 17, Docker, and the project's checked-in Gradle wrapper.

To reproduce the JFrog-backed build, supply credentials through the environment
from a private source:

```bash
export JFROG_GRADLE_REPOSITORY_URL='https://trialbf1216.jfrog.io/artifactory/gradle-virtual'
export JFROG_USERNAME='your-jfrog-username'
export JFROG_IDENTITY_TOKEN='your-jfrog-identity-token'

./gradlew clean build
docker build --tag spring-petclinic:local .
docker run --rm --name spring-petclinic --publish 8080:8080 spring-petclinic:local
```

Open <http://localhost:8080/>. The credentials are needed only for Gradle; they
are not passed to Docker or stored in the image.

## Jenkins artifacts

Successful builds provide the tested JAR, a Docker image archive, and its
SHA-256 checksum. After downloading the archived files from Jenkins:

```bash
sha256sum --check spring-petclinic-image.tar.sha256
docker load --input spring-petclinic-image.tar
docker run --rm --publish 8080:8080 spring-petclinic:verified
```

On macOS, use `shasum -a 256 spring-petclinic-image.tar` and compare it with
the archived checksum.

## Dependency provenance

The verified security boundary is that the Gradle client talks to JFrog rather
than contacting Maven Central directly. JFrog may then serve its cache or proxy
an approved upstream repository, which is the intended behavior.

Gradle also verifies resolved artifacts against the committed checksum
baseline, and the wrapper verifies the Gradle distribution checksum before
using it.

To verify the path independently, use an empty Gradle cache and dependency
refresh:

```bash
GRADLE_USER_HOME="$(mktemp -d)" \
  ./gradlew --no-daemon --refresh-dependencies test bootJar --info
```

The log should contain requests to the JFrog virtual repository and no direct
requests to `repo.maven.apache.org`. `--refresh-dependencies` is a provenance
check rather than a normal Jenkins option, so regular CI can reuse JFrog and
Gradle caches.

## Potential future improvements

The current pipeline is intentionally focused on the required build, test,
container, and JFrog Cloud flow. The following are measured follow-on
improvements for a larger or longer-lived delivery platform.

| # | Area | Potential improvement | Expected benefit |
| ---: | --- | --- | --- |
| 1 | Warning hygiene | Fix actionable warnings; track unavoidable tool noise. | Keeps regressions visible. |
| 2 | Incremental builds | Use `./gradlew build` routinely; reserve `clean build` for release checks. | Avoids repeated work. |
| 3 | Gradle caching | Persist a controlled cache; evaluate build and configuration cache. | Reuses dependencies and task outputs. |
| 4 | Build dependency graph | Favor Gradle's dependency graph over sequential scripts; enable measured `--parallel` work. | Shortens the critical path. |
| 5 | Test execution | Split suites; parallelize only isolated tests. | Speeds tests without flakiness. |
| 6 | Test cadence | Run fast tests per change; run long environment tests on scheduled and release paths. | Balances speed and coverage. |
| 7 | Avoid unnecessary builds | Skip application builds for documentation-only changes. | Saves CI capacity. |
| 8 | JFrog governance | Publish Build Info, add Xray gates, and promote immutable builds. | Improves traceability and release control. |
| 9 | Image supply chain | Publish immutable tags and digests; associate the SBOM and provenance. | Strengthens traceability and security. |
| 10 | Artifact versioning | Keep the source version stable; add the Jenkins build number and Git SHA to archived JAR and image identities. | Makes every deliverable traceable. |
| 11 | CI operations | Add metrics, report links, portable smoke tests, and failure alerts. | Improves operation and recovery. |

### Why Gradle and the wrapper

Maven stubbornly persists, but Gradle is simply nicer to evolve. Its readable
build logic, dependency-aware execution, and caching model suit a CI pipeline
that will grow over time. With `./gradlew`, the repository brings its own build
tool; agents need only Java, plus Docker for image work.
