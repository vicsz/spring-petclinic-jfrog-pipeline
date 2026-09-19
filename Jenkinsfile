pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timeout(time: 20, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '3'))
    }

    environment {
        IMAGE_NAME = "spring-petclinic:jenkins-${env.BUILD_NUMBER}"
        DELIVERABLE_IMAGE_NAME = 'spring-petclinic:verified'
        CONTAINER_NAME = "spring-petclinic-jenkins-smoke-${env.BUILD_NUMBER}"
        JFROG_GRADLE_REPOSITORY_URL = 'https://trialbf1216.jfrog.io/artifactory/gradle-virtual'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Verify and build') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'jfrog-cloud-gradle',
                    usernameVariable: 'JFROG_USERNAME', passwordVariable: 'JFROG_IDENTITY_TOKEN')]) {
                    sh './gradlew clean build'
                }
            }
        }

        stage('Build Docker image') {
            steps {
                sh '''
                    set -eu
                    if [ ! -f build/libs/petclinic.jar ]; then
                        echo 'Expected build/libs/petclinic.jar from the Gradle build' >&2
                        exit 1
                    fi
                    docker build --tag "$IMAGE_NAME" .
                '''
            }
        }

        stage('Smoke test image') {
            steps {
                sh '''
                    set -eu
                    docker rm --force "$CONTAINER_NAME" >/dev/null 2>&1 || true
                    trap 'docker rm --force "$CONTAINER_NAME" >/dev/null 2>&1 || true' EXIT
                    docker run --detach --name "$CONTAINER_NAME" --publish 0:8080 "$IMAGE_NAME"
                    SMOKE_PORT="$(docker port "$CONTAINER_NAME" 8080/tcp | sed -n '1s/.*://p')"
                    if [ -z "$SMOKE_PORT" ]; then
                        echo 'Docker did not publish a smoke-test port' >&2
                        docker logs "$CONTAINER_NAME" >&2 || true
                        exit 1
                    fi
                    HTTP_SCHEME='http'
                    HEALTH_URL="${HTTP_SCHEME}://host.docker.internal:${SMOKE_PORT}/"
                    for attempt in $(seq 1 30); do
                        if curl --fail --silent --show-error "$HEALTH_URL" >/dev/null; then
                            exit 0
                        fi
                        sleep 2
                    done
                    echo 'Petclinic did not become ready in time' >&2
                    docker logs "$CONTAINER_NAME" >&2 || true
                    exit 1
                '''
            }
        }

        stage('Package deliverables') {
            steps {
                sh '''
                    set -eu
                    mkdir -p build/deliverables
                    docker tag "$IMAGE_NAME" "$DELIVERABLE_IMAGE_NAME"
                    docker save --output build/deliverables/spring-petclinic-image.tar "$DELIVERABLE_IMAGE_NAME"
                    (
                        cd build/deliverables
                        sha256sum spring-petclinic-image.tar > spring-petclinic-image.tar.sha256
                    )
                '''
                archiveArtifacts artifacts: 'build/libs/petclinic.jar,build/deliverables/*', fingerprint: true
            }
        }
    }

    post {
        always {
            junit allowEmptyResults: true, testResults: 'build/test-results/test/*.xml'
            archiveArtifacts artifacts: 'build/reports/**', allowEmptyArchive: true
            sh '''
                docker rm --force "$CONTAINER_NAME" >/dev/null 2>&1 || true
                docker image rm "$DELIVERABLE_IMAGE_NAME" "$IMAGE_NAME" >/dev/null 2>&1 || true
            '''
        }
    }
}
