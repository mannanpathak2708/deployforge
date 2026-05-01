# syntax=docker/dockerfile:1.6
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /build
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn clean package -DskipTests -B

FROM gcr.io/distroless/java17-debian12:nonroot
WORKDIR /app
COPY --from=builder --chown=nonroot:nonroot /build/target/taskmanager.jar /app/app.jar
EXPOSE 8080
ENV JAVA_TOOL_OPTIONS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UseG1GC"
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
