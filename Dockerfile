# Build the application with the project's pinned Gradle wrapper.
FROM eclipse-temurin:17-jdk AS build

WORKDIR /workspace
COPY . .

RUN chmod +x ./gradlew \
    && ./gradlew --no-daemon test bootJar

# Keep the runtime image smaller than the build image.
FROM eclipse-temurin:17-jre

WORKDIR /app
COPY --from=build /workspace/build/libs/*.jar /app/petclinic.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/petclinic.jar"]
