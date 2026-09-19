# Spring Petclinic JFrog pipeline

This repository packages Spring Petclinic as a Docker image through a Jenkins
pipeline. The Jenkins build resolves Gradle plugins and project dependencies
through a JFrog Cloud virtual Maven repository, runs the test suite, builds the
image, and verifies the running container with an HTTP smoke test.

The required JFrog Cloud path is implemented. The self-hosted Artifactory
deployment described in the assignment is an optional bonus and is not part of
the current pipeline.

![Jenkins and JFrog pipeline flow](assets/jfrog-pipeline-flow.png)

## What is included

- `Jenkinsfile` — checkout, JFrog-backed Gradle build, Docker image build, and
  ephemeral-port smoke test.
- `Dockerfile` — multi-stage Java 17 build and runtime image.
- `build.gradle` and `settings.gradle` — configurable JFrog repository and
  plugin resolution.
- `.github/workflows/gradle-build.yml` and
  `.github/workflows/maven-build.yml` — independent GitHub Actions validation.
- `assets/jfrog-pipeline-flow.png` — pipeline overview diagram.
- `local/` — ignored local notes and credentials; it is not required for a
  clean checkout and must never be committed.

## Prerequisites

- Git
- Java 17 (the Gradle toolchain targets Java 17)
- Docker Desktop or another Docker Engine
- Network access to GitHub and JFrog Cloud
- JFrog username and identity token only when running the JFrog-backed build
  locally

The wrapper downloads the required Gradle version automatically. If Gradle
reports that Java 17 is missing, install a Java 17 JDK and set `JAVA_HOME` to
that installation before running the commands below.

## Build and test locally

The default local mode uses Maven Central when the JFrog environment variables
are not set:

```bash
./gradlew --no-daemon test bootJar
```

This fallback keeps the repository easy to build from a clean checkout. The
Jenkins pipeline always sets the JFrog variables and therefore exercises the
JFrog-backed path.

## Resolve dependencies through JFrog Cloud

The configured JFrog virtual repository is:

```text
https://trialbf1216.jfrog.io/artifactory/gradle-virtual
```

That virtual repository combines:

- `maven-central` — remote Maven Central proxy
- `gradle-plugins` — Maven proxy for Gradle Plugin Portal artifacts
- `gradle-local` — local deployment repository

For a local JFrog-backed build, export the following values from a private
ignored source. Do not put a username, token, password, or token-bearing URL
in this README or in the repository:

```bash
export JFROG_GRADLE_REPOSITORY_URL='https://trialbf1216.jfrog.io/artifactory/gradle-virtual'
export JFROG_USERNAME='your-jfrog-username'
export JFROG_IDENTITY_TOKEN='your-jfrog-identity-token'

./gradlew --no-daemon --refresh-dependencies test bootJar
```

The build fails early if the repository URL is set without both credential
variables. When the variables are set, both `settings.gradle` plugin
resolution and `build.gradle` dependency resolution use only the JFrog virtual
repository.

## Verify dependency provenance

The useful claim to verify is that the **Gradle client did not contact Maven
Central directly**. JFrog may still proxy or cache its configured Maven
Central remote repository internally; that is expected behavior for a virtual
repository.

Use a fresh Gradle cache and informational request logging:

```bash
set -o pipefail
verification_log="$(mktemp)"
GRADLE_USER_HOME="$(mktemp -d)" \
  ./gradlew --no-daemon --refresh-dependencies test bootJar --info \
  2>&1 | tee "$verification_log"

grep -q 'trialbf1216.jfrog.io/artifactory/gradle-virtual' "$verification_log"
if grep -Eq 'repo\.maven\.apache\.org|MavenRepo' "$verification_log"; then
  echo 'Direct Maven Central traffic detected' >&2
  exit 1
fi
```

The independent clean-cache verification for commit `a4ea0cb` completed
successfully in about one minute, recorded 927 JFrog virtual-repository URL
hits, and recorded no direct Maven Central URL hits. Request-log wording can
vary by Gradle version, so this evidence check is documented rather than made
part of the normal build gate.

## Build and run the Docker image

Build the local image:

```bash
docker build --tag spring-petclinic:local .
```

Run it in the foreground:

```bash
docker run --rm \
  --name spring-petclinic \
  --publish 8080:8080 \
  spring-petclinic:local
```

Open <http://localhost:8080/> in a browser. Stop the foreground container with
`Ctrl-C`. If you started it detached, clean it up with:

```bash
docker rm --force spring-petclinic
```

To create the assignment's runnable image attachment locally:

```bash
docker save spring-petclinic:local --output spring-petclinic.tar
```

The image file is a submission artifact, not source control content.

## Jenkins pipeline

Create a Jenkins Pipeline job using this GitHub repository and the `main`
branch, with the `Jenkinsfile` loaded from SCM. Add a Jenkins username/password
credential with this ID:

```text
jfrog-cloud-gradle
```

Use the JFrog account username as the credential username and the JFrog
identity token as the credential password. The pipeline binds those values
only for the Gradle build; no secret is embedded in the Jenkinsfile or the
public repository.

The stages are:

1. Checkout the repository from SCM.
2. Run `./gradlew --no-daemon --refresh-dependencies test bootJar` through the
   JFrog virtual repository.
3. Build `spring-petclinic:jenkins` from the Dockerfile.
4. Start the image on an ephemeral host port and poll the application over
   HTTP.
5. Remove the smoke-test container in both success and failure paths.

The smoke test intentionally uses an ephemeral host port, so it does not
depend on port `18080` being free on the Jenkins host.

## GitHub Actions validation

The Maven and Gradle workflows provide independent build validation on GitHub.
They do not receive the private JFrog credential and therefore use the normal
public-repository fallback. The assignment's JFrog verification is the
SCM-backed Jenkins pipeline described above.

## Verification evidence

The following checks passed for commit `a4ea0cb`:

- Local Java 17 Gradle tests and `bootJar`.
- Local Docker image build.
- Jenkins build #9, including JFrog-backed Gradle resolution, Docker build,
  and HTTP smoke test.
- GitHub Actions Maven workflow.
- GitHub Actions Gradle workflow.
- Fresh-cache JFrog provenance run with no direct Maven Central URL requests.

## Troubleshooting

### Java toolchain errors

Install a Java 17 JDK and set `JAVA_HOME` to it. The project intentionally
compiles against Java 17 even if a newer JDK is installed.

### JFrog authentication errors

Confirm that all three JFrog variables are present and that the token is an
identity token, not a UI password. In Jenkins, confirm the credential ID is
exactly `jfrog-cloud-gradle`. Never add the token to a command line, URL, or
committed file.

### Docker port conflicts

The local example uses port `8080`; choose another host port if needed, for
example `--publish 18080:8080`. Jenkins uses an ephemeral port automatically.

### Jenkins smoke test cannot reach the container

The pipeline assumes the Jenkins agent can run Docker and resolve
`host.docker.internal`. Confirm Docker socket/CLI access and that the image
starts successfully before investigating the HTTP polling loop.

## Security and portability notes

The JFrog repository URL is public configuration metadata. It is safe to show
the HTTPS endpoint here because it contains no credentials, signed query
parameters, or embedded authentication. Credentials are supplied at runtime
through Jenkins and private local environment variables.

The trial-host URL is intentionally visible for this assignment. For a
reusable production template, move the endpoint into Jenkins/job configuration
while retaining the `JFROG_GRADLE_REPOSITORY_URL` variable name.

## References

- [Gradle repository declarations](https://docs.gradle.org/current/userguide/declaring_repositories.html)
- [Gradle repository protocols and credential handling](https://docs.gradle.org/current/userguide/supported_repository_protocols.html)
- [Gradle on Jenkins](https://docs.gradle.org/current/userguide/jenkins.html)
