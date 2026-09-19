FROM eclipse-temurin:17-jre@sha256:bd25c61779663bc2df8ced059f1cc114fafc073afe16125c13fcc3a37fecd845

WORKDIR /app

# Jenkins builds and tests this executable JAR through the authenticated JFrog
# repository before Docker packages it. The .dockerignore file exposes only
# this artifact to the Docker build context.
COPY --chown=10001:10001 build/libs/petclinic.jar /app/petclinic.jar

EXPOSE 8080
USER 10001:10001
ENTRYPOINT ["java", "-jar", "/app/petclinic.jar"]
