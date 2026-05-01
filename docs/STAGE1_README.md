# DeployForge — Stage 1 of 4

**Spring Boot application + Docker + Kubernetes manifests**

This is the first deliverable of the *DeployForge: Self-Managed Kubernetes Platform on AWS* project — the cloud-native counterpart to the Redify CPPE project, rebuilt around the Essentials in Cloud and DevOps course toolchain (Terraform, Ansible, Docker, Kubernetes-on-EC2, GitHub Actions).

---

## What's in this stage

```
app/                          Spring Boot 3.2 task management service
├── pom.xml                   Maven build (Java 17, JaCoCo, Flyway, Actuator)
├── mvnw + .mvn/              Maven wrapper (no local Maven install needed)
├── Dockerfile                Multi-stage build → distroless runtime (~180MB)
├── .dockerignore
└── src/
    ├── main/java/com/deployforge/taskmanager/
    │   ├── TaskManagerApplication.java
    │   ├── controller/TaskController.java
    │   ├── model/{Task,TaskStatus,Priority}.java
    │   ├── repository/TaskRepository.java
    │   └── service/TaskService.java
    ├── main/resources/
    │   ├── application.yml            (default + prod profile)
    │   ├── application-test.yml       (H2 in-memory for tests)
    │   └── db/migration/V1__create_tasks_table.sql
    └── test/java/com/deployforge/taskmanager/
        ├── TaskServiceTest.java               (8 unit tests, Mockito)
        └── TaskControllerIntegrationTest.java (8 integration tests, MockMvc + H2)

k8s/
├── base/                     Kustomize base (all 9 resources)
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── secret.example.yaml   ← template only; real one created by Ansible
│   ├── postgres.yaml         (StatefulSet + headless Service + 5Gi PVC)
│   ├── deployment.yaml       (rolling update, probes, resource limits, security context)
│   ├── service.yaml
│   ├── ingress.yaml          (NGINX ingress — installed by Ansible Stage 3)
│   ├── hpa.yaml              (CPU 70% / mem 80%, 2-6 replicas)
│   ├── rbac.yaml             (deployer ServiceAccount + Role for CI)
│   └── networkpolicy.yaml    (default deny + selective allow)
└── overlays/prod/            Production overrides (3 replicas, scale to 10)
```

---

## Why these specific design decisions

The viva will ask. Short answers ready:

| Choice | Reason |
|---|---|
| **Distroless runtime image** | No shell, no package manager → drastically fewer Trivy CVE hits. Image is ~180MB vs ~450MB for `eclipse-temurin:17-jre`. |
| **`runAsNonRoot` + `readOnlyRootFilesystem`** | CIS Kubernetes Benchmark requirements. Distroless ships uid 65532. |
| **Kustomize base + overlay** | Same manifests for staging/prod with different replica counts. Industry standard. |
| **HPA on CPU + memory** | Demonstrates auto-scaling — one of Redify's listed future enhancements. |
| **NetworkPolicy default-deny** | Defence in depth. Calico CNI (installed in Stage 3) enforces it. |
| **Liveness/readiness/startup probes (all three)** | Slow Spring Boot cold start would cause CrashLoopBackOff without `startupProbe`. Standard production pattern. |
| **PostgreSQL StatefulSet (not Deployment)** | Stable network identity + persistent volume. Deployments lose data on rescheduling. |
| **Flyway migrations** | Schema is versioned in git, applied automatically. Same approach Redify used. |

---

## How to run locally (for your own testing)

You need Docker installed. Postgres comes from `docker run`, the app comes from the JAR.

```bash
# 1. Start a local Postgres
docker run -d --name dev-pg \
  -e POSTGRES_USER=taskuser \
  -e POSTGRES_PASSWORD=changeme \
  -e POSTGRES_DB=taskdb \
  -p 5432:5432 \
  postgres:15-alpine

# 2. Build and run the app
cd app
./mvnw spring-boot:run

# 3. Hit it
curl http://localhost:8080/actuator/health
curl http://localhost:8080/api/tasks

# 4. Create a task
curl -X POST http://localhost:8080/api/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"Set up kubeadm master","priority":"HIGH","status":"TODO"}'
```

To build the Docker image locally:

```bash
cd app
docker build -t deployforge/taskmanager:dev .
```

To run the test suite (16 tests, ~78%+ line coverage by JaCoCo):

```bash
cd app
./mvnw test
# Coverage report: target/site/jacoco/index.html
```

---

## How this connects to Stages 2–4

- **Stage 2 (Terraform)** provisions the AWS infrastructure: VPC, 2 public subnets, security groups, IAM, ECR repository, and 4 EC2s (1 bastion + 1 master + 2 workers).
- **Stage 3 (Ansible)** logs into the EC2s via the bastion, installs containerd + kubeadm + kubelet, initialises the master (`kubeadm init`), joins the workers, deploys Calico CNI + NGINX ingress + local-path provisioner + kube-prometheus-stack, then applies these k8s manifests.
- **Stage 4 (GitHub Actions)** runs on every push to `main`: Maven test → Trivy filesystem scan → Docker build → Trivy image scan → push to ECR → `kubectl set image` against the deployer ServiceAccount token from Stage 3.

The image reference `ghcr.io/deployforge/taskmanager:latest` in `deployment.yaml` is overridden by the GitHub Actions workflow with the actual ECR registry URL + git SHA tag. That keeps the manifest immutable and the deployment deterministic.

---

## What needs to change before this is "yours"

1. `pom.xml` → groupId/artifactId if you want a different package name
2. `application.yml` → the `info.app.*` block
3. `k8s/base/ingress.yaml` → swap `taskmanager.local` for your master's public DNS or your real domain
4. The `images.newTag` in `k8s/base/kustomization.yaml` will get patched by CI — leave as-is

Stage 2 starts when you give the go-ahead.
