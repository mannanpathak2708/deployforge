# Jenkins CI/CD Pipeline — DeployForge

Local Jenkins (Docker) running on your Mac, hooked up to GitHub via ngrok webhook tunnel, deploying to the EC2 Kubernetes cluster.

## Architecture

```
GitHub repo (mannanpathak2708/deployforge)
   │
   │ webhook on push to main
   ▼
ngrok tunnel (https://xxxx.ngrok.io)
   │
   ▼
Jenkins on Mac (localhost:8080)
   │ runs 10-stage Jenkinsfile pipeline
   │  1. Checkout       6. Docker build
   │  2. Compile        7. Trivy image scan
   │  3. Tests          8. Push to ECR
   │  4. Trivy fs scan  9. Deploy to K8s (kubectl set image)
   │  5. Build JAR     10. Smoke test
   ▼
AWS ECR (image push)  +  EC2 master (SSH for kubectl)
   │                          │
   └──────────►  K8s rolling update  ◄──┘
```

## One-time setup (~15 min)

### 1. Start Jenkins

```bash
cd ~/Downloads/Repo/deployforge/jenkins
docker compose up -d

# Wait for it to be ready
docker logs -f deployforge-jenkins
# Look for: "Jenkins is fully up and running"
# Ctrl+C when you see it
```

Open http://localhost:8080 — you'll be at the Jenkins dashboard.

> **Note:** the `setup-wizard` is disabled by `JAVA_OPTS=-Djenkins.install.runSetupWizard=false`, so there's no admin password prompt. For local-only demo this is fine; for production you'd absolutely set up auth.

### 2. Install required plugins

Manage Jenkins → **Plugins** → **Available plugins** → search and install (then restart):

- `Docker Pipeline`
- `AWS Credentials`
- `SSH Agent`
- `GitHub`
- `AnsiColor`
- `Pipeline: Stage View`
- `Timestamper`
- `JUnit`

Click **Install** then check **Restart Jenkins when installation is complete**.

### 3. Install Docker CLI + AWS CLI inside the container

Jenkins runs as root in this setup, so we can install tools easily:

```bash
docker exec -u 0 deployforge-jenkins bash -c '
  apt-get update -qq && \
  apt-get install -y -qq docker.io curl unzip && \
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
  cd /tmp && unzip -q awscliv2.zip && ./aws/install && rm -rf aws awscliv2.zip
'
docker exec deployforge-jenkins docker --version
docker exec deployforge-jenkins aws --version
```

Both should report a version. If they do, the pipeline can use docker and aws inside.

### 4. Add credentials in Jenkins

Manage Jenkins → **Credentials** → System → Global credentials → **Add Credentials**

#### Credential 1: AWS access keys

- **Kind**: AWS Credentials
- **ID**: `aws-creds` (must match Jenkinsfile)
- **Access Key ID**: your `deployforge-cicd` IAM user's access key
- **Secret Access Key**: that user's secret

If you didn't create a CI/CD IAM user yet:

```bash
aws iam create-user --user-name deployforge-cicd
aws iam attach-user-policy --user-name deployforge-cicd \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
aws iam create-access-key --user-name deployforge-cicd
# Save the AccessKeyId + SecretAccessKey from output
```

#### Credential 2: GitHub PAT (for the webhook to authenticate Jenkins back to GitHub)

- **Kind**: Username with password
- **ID**: `github-pat`
- **Username**: `mannanpathak2708`
- **Password**: a GitHub personal access token with `repo` and `admin:repo_hook` scopes

### 5. Create the pipeline job

Dashboard → **New Item** → name it `deployforge-pipeline` → **Pipeline** → OK

Configure the job:

- **GitHub project**: `https://github.com/mannanpathak2708/deployforge`
- **Build Triggers**: ✅ check **GitHub hook trigger for GITScm polling**
- **Pipeline**:
  - Definition: **Pipeline script from SCM**
  - SCM: **Git**
  - Repo URL: `https://github.com/mannanpathak2708/deployforge.git`
  - Credentials: select your `github-pat`
  - Branch: `*/main`
  - Script Path: `Jenkinsfile`
- Click **Save**

### 6. Make Jenkins reachable from GitHub via ngrok

Jenkins is at `localhost:8080`, GitHub can't reach that. Tunnel it:

```bash
brew install ngrok
ngrok config add-authtoken YOUR_NGROK_TOKEN  # sign up free at ngrok.com
ngrok http 8080
```

You'll see something like:

```
Forwarding https://abcd-12-34-56-78.ngrok-free.app -> http://localhost:8080
```

**Copy that https URL.** Leave the ngrok terminal window open — closing it kills the tunnel.

### 7. Configure GitHub webhook

GitHub → your `deployforge` repo → **Settings** → **Webhooks** → **Add webhook**

- **Payload URL**: `https://abcd-12-34-56-78.ngrok-free.app/github-webhook/` (note the trailing `/`)
- **Content type**: `application/json`
- **Secret**: leave blank for the demo (in production you'd set one)
- **Which events**: ✅ Just the push event
- **Active**: ✅
- Click **Add webhook**

GitHub will immediately ping the URL — refresh the page and you should see a green ✅ next to the recent delivery.

### 8. Test the pipeline manually first

Jenkins dashboard → click `deployforge-pipeline` → **Build Now** (left sidebar).

Watch the stage view populate. First build downloads Maven dependencies inside Docker, takes ~5 min. Subsequent builds are faster.

Successful run = all 10 stages green.

### 9. Test the auto-trigger via webhook

```bash
cd ~/Downloads/Repo/deployforge
# Trivial change
echo "// Jenkins demo $(date)" >> app/src/main/java/com/deployforge/taskmanager/TaskManagerApplication.java
git add app/
git commit -m "demo: trigger Jenkins pipeline"
git push
```

Within 5 seconds you should see a new build start in Jenkins. **That's your live demo.**

## Demo flow for the review (3-5 min)

1. Open Jenkins dashboard at `http://localhost:8080` — show the `deployforge-pipeline` job
2. Show the previous successful build with all 10 stages green
3. Open VS Code, make a small visible change (e.g. log message in `TaskManagerApplication.java`)
4. `git push` from terminal
5. Within seconds, Jenkins shows a new build starting
6. Walk through stages live as they execute (~3-5 min total)
7. After build completes, refresh the app at `http://44.195.19.229:30081` and show the new pod is serving (check `kubectl get pods` — new pod ID, AGE = seconds)

## Common errors and fixes

| Error | Fix |
|---|---|
| `docker: command not found` in pipeline | Step 3 didn't run — re-run the `apt-get install docker.io` command |
| `aws: command not found` | Same — re-run the AWS CLI install |
| Webhook doesn't trigger build | Check ngrok terminal is still running; check GitHub webhook deliveries page for errors |
| Pipeline fails on stage 8 (push) | AWS creds wrong; verify `aws-creds` Jenkins credential matches your IAM user |
| Pipeline fails on stage 9 (deploy) | SSH key issue; check the docker-compose.yml mounted the .pem correctly |
| `permission denied` on Docker socket | Mac Docker Desktop sometimes needs Settings → General → "Use the new Virtualization framework" toggled |
| Stage 7 fails: CRITICAL CVE found | Trivy found a real vuln. For demo, change `--exit-code 1` to `--exit-code 0` in Jenkinsfile temporarily |

## Cleanup after review

```bash
# Stop Jenkins
cd ~/Downloads/Repo/deployforge/jenkins
docker compose down

# Optionally also remove the persistent volume (loses Jenkins config)
docker compose down -v

# Stop ngrok: just close that terminal window
```

## What this stage demonstrates

For the report's CI/CD chapter:

| Element | Implementation |
|---|---|
| Source control trigger | GitHub webhook → ngrok → Jenkins |
| Build pipeline as code | Declarative `Jenkinsfile` in repo root |
| 10 stages | Checkout → Compile → Test → FS Scan → Build JAR → Image Build → Image Scan → Push → Deploy → Smoke Test |
| Automated tests | JUnit/Mockito test results published in Jenkins UI |
| Security scanning | Trivy at filesystem and image levels |
| Artifact management | JAR archived per build; Docker images tagged `build-<n>` in ECR |
| Deployment automation | `kubectl set image` rolling update via SSH |
| Verification | Post-deploy smoke test against `/actuator/health` |
| Failure handling | Build halts at any failed stage, console output shows exact error |

That's a complete, defensible CI/CD story for the viva.
