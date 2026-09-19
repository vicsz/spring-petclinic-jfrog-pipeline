pipeline {
    agent any

    environment {
        IMAGE_NAME = 'spring-petclinic:jenkins'
        CONTAINER_NAME = 'spring-petclinic-jenkins-smoke'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build and test') {
            steps {
                sh './gradlew --no-daemon test bootJar'
            }
        }

        stage('Build Docker image') {
            steps {
                sh 'docker build --tag "$IMAGE_NAME" .'
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
                    HTTP_SCHEME='http'
                    HEALTH_URL="${HTTP_SCHEME}://host.docker.internal:${SMOKE_PORT}/"
                    for attempt in $(seq 1 30); do
                        if curl --fail --silent --show-error "$HEALTH_URL" >/dev/null; then
                            exit 0
                        fi
                        sleep 2
                    done
                    echo 'Petclinic did not become ready in time' >&2
                    exit 1
                '''
            }
        }
    }

    post {
        always {
            sh 'docker rm --force "$CONTAINER_NAME" >/dev/null 2>&1 || true'
        }
    }
}
