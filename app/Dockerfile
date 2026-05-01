# syntax=docker/dockerfile:1.6
# ----------------------------------------------------------------------------
# Stage 1: Build the JAR using Maven
# ----------------------------------------------------------------------------
FROM eclipse-temurin:17-jdk-jammy AS builder

WORKDIR /build

# Copy Maven wrapper + descriptor first to leverage Docker layer caching:
# dependencies are only re-downloaded when pom.xml changes, not on every code edit.
COPY pom.xml .
COPY .mvn/ .mvn/
COPY mvnw .
RUN chmod +x mvnw && ./mvnw dependency:go-offline -B

# Now copy the source and build the JAR
COPY src ./src
RUN ./mvnw clean package -DskipTests -B

# ----------------------------------------------------------------------------
# Stage 2: Runtime — distroless minimises the attack surface for Trivy
# ----------------------------------------------------------------------------
FROM gcr.io/distroless/java17-debian12:nonroot

WORKDIR /app

# nonroot user (uid 65532) is provided by the distroless image
COPY --from=builder --chown=nonroot:nonroot /build/target/taskmanager.jar /app/app.jar

EXPOSE 8080

# Kubernetes liveness/readiness probes hit /actuator/health/liveness and /readiness
# JVM tuning: respect container memory limits, prefer G1
ENV JAVA_TOOL_OPTIONS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UseG1GC"

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
