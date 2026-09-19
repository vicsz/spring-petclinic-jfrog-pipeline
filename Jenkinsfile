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
                    docker run --detach --name "$CONTAINER_NAME" --publish 18080:8080 "$IMAGE_NAME"
                    trap 'docker rm --force "$CONTAINER_NAME" >/dev/null 2>&1 || true' EXIT
                    for attempt in $(seq 1 30); do
                        if curl --fail --silent http://host.docker.internal:18080/ >/dev/null; then
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
