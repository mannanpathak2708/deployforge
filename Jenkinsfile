// ============================================================================
//  DeployForge — Jenkins Declarative Pipeline
//
//  10-stage pipeline that mirrors Redify's CPPE structure:
//    1.  Git Checkout
//    2.  Compile
//    3.  Unit + Integration Tests
//    4.  Trivy Filesystem Scan
//    5.  Build JAR
//    6.  Docker Image Build
//    7.  Trivy Image Scan
//    8.  Push to ECR
//    9.  Deploy to Kubernetes
//    10. Smoke Test
//
//  Triggers on GitHub webhook (set up via ngrok for local demo).
// ============================================================================

pipeline {
    agent any

    options {
        timeout(time: 20, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        ansiColor('xterm')
    }

    environment {
        AWS_REGION       = 'us-east-1'
        AWS_ACCOUNT_ID   = '560205084884'
        ECR_REGISTRY     = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        ECR_REPO         = 'deployforge/taskmanager'
        IMAGE_TAG        = "build-${BUILD_NUMBER}"
        FULL_IMAGE       = "${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"

        K8S_NAMESPACE    = 'deployforge'
        K8S_DEPLOYMENT   = 'taskmanager'
        K8S_CONTAINER    = 'taskmanager'
        MASTER_HOST      = '44.195.19.229'

        // Jenkins credentials IDs (configured in Jenkins UI)
        AWS_CREDS        = 'aws-creds'
        SSH_CREDS        = 'ec2-ssh-key'
    }

    triggers {
        // Webhook trigger configured via "GitHub hook trigger for GITScm polling"
        // checkbox in the job config. ngrok forwards GitHub's webhook to Jenkins.
        githubPush()
    }

    stages {

        // -------------------------------------------------------------
        // Stage 1: Git Checkout
        // -------------------------------------------------------------
        stage('1. Git Checkout') {
            steps {
                checkout scm
                sh 'git log -1 --pretty=format:"Building %h: %s by %an"'
            }
        }

        // -------------------------------------------------------------
        // Stage 2: Compile (validates code structure quickly)
        // -------------------------------------------------------------
        stage('2. Compile') {
            steps {
                dir('app') {
                    sh '''
                        docker run --rm -v "$PWD":/build -w /build \
                          maven:3.9-eclipse-temurin-17 \
                          mvn -B compile
                    '''
                }
            }
        }

        // -------------------------------------------------------------
        // Stage 3: Unit + Integration Tests
        // -------------------------------------------------------------
        stage('3. Tests') {
            steps {
                dir('app') {
                    sh '''
                        docker run --rm -v "$PWD":/build -w /build \
                          maven:3.9-eclipse-temurin-17 \
                          mvn -B test
                    '''
                }
            }
            post {
                always {
                    junit allowEmptyResults: true,
                          testResults: 'app/target/surefire-reports/*.xml'
                }
            }
        }

        // -------------------------------------------------------------
        // Stage 4: Trivy Filesystem Scan
        // -------------------------------------------------------------
        stage('4. Trivy FS Scan') {
            steps {
                sh '''
                    docker run --rm -v "$PWD":/scan \
                      aquasec/trivy:latest fs \
                      --severity HIGH,CRITICAL \
                      --ignore-unfixed \
                      --exit-code 0 \
                      /scan/app
                '''
            }
        }

        // -------------------------------------------------------------
        // Stage 5: Build JAR (produces target/taskmanager.jar for the image)
        // -------------------------------------------------------------
        stage('5. Build JAR') {
            steps {
                dir('app') {
                    sh '''
                        docker run --rm -v "$PWD":/build -w /build \
                          maven:3.9-eclipse-temurin-17 \
                          mvn -B package -DskipTests
                    '''
                }
                archiveArtifacts artifacts: 'app/target/taskmanager.jar',
                                 fingerprint: true
            }
        }

        // -------------------------------------------------------------
        // Stage 6: Docker Image Build
        // -------------------------------------------------------------
        stage('6. Docker Build') {
            steps {
                dir('app') {
                    sh "docker build --platform linux/amd64 -t ${FULL_IMAGE} -t ${ECR_REGISTRY}/${ECR_REPO}:latest ."
                }
            }
        }

        // -------------------------------------------------------------
        // Stage 7: Trivy Image Scan (CRITICAL = build fails)
        // -------------------------------------------------------------
        stage('7. Trivy Image Scan') {
            steps {
                sh '''
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                      aquasec/trivy:latest image \
                      --severity CRITICAL \
                      --ignore-unfixed \
                      --exit-code 1 \
                      ''' + "${FULL_IMAGE}"
            }
        }

        // -------------------------------------------------------------
        // Stage 8: Push to AWS ECR
        // -------------------------------------------------------------
        stage('8. Push to ECR') {
            steps {
                withCredentials([[
                    $class:           'AmazonWebServicesCredentialsBinding',
                    credentialsId:    "${AWS_CREDS}",
                    accessKeyVariable:'AWS_ACCESS_KEY_ID',
                    secretKeyVariable:'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh '''
                        aws ecr get-login-password --region ${AWS_REGION} \
                          | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                        docker push ${FULL_IMAGE}
                        docker push ${ECR_REGISTRY}/${ECR_REPO}:latest
                    '''
                }
            }
        }

        // -------------------------------------------------------------
        // Stage 9: Deploy to Kubernetes (rolling update via SSH + kubectl)
        // -------------------------------------------------------------
        stage('9. Deploy to K8s') {
            steps {
                withCredentials([[
                    $class:           'AmazonWebServicesCredentialsBinding',
                    credentialsId:    "${AWS_CREDS}",
                    accessKeyVariable:'AWS_ACCESS_KEY_ID',
                    secretKeyVariable:'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh '''
                        chmod 600 /var/jenkins_home/.ssh/deployforge-key.pem
                        ssh -o StrictHostKeyChecking=no \
                            -i /var/jenkins_home/.ssh/deployforge-key.pem \
                            ubuntu@${MASTER_HOST} bash -s <<EOF
                            set -e
                            # Refresh ECR pull secret (token expires every 12h)
                            PASS=\\$(AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} aws ecr get-login-password --region ${AWS_REGION})
                            kubectl create secret docker-registry ecr-registry \\
                              --docker-server=${ECR_REGISTRY} \\
                              --docker-username=AWS \\
                              --docker-password="\\$PASS" \\
                              -n ${K8S_NAMESPACE} \\
                              --dry-run=client -o yaml | kubectl apply -f -

                            # Roll the deployment to the new image
                            kubectl set image deployment/${K8S_DEPLOYMENT} \\
                              ${K8S_CONTAINER}=${FULL_IMAGE} \\
                              -n ${K8S_NAMESPACE}

                            kubectl rollout status deployment/${K8S_DEPLOYMENT} \\
                              -n ${K8S_NAMESPACE} --timeout=300s
EOF
                    '''
                }
            }
        }

        // -------------------------------------------------------------
        // Stage 10: Smoke Test
        // -------------------------------------------------------------
        stage('10. Smoke Test') {
            steps {
                sh '''
                    ssh -o StrictHostKeyChecking=no \
                        -i /var/jenkins_home/.ssh/deployforge-key.pem \
                        ubuntu@${MASTER_HOST} bash -s <<'EOF'
                        set -e
                        CIP=$(kubectl get svc taskmanager -n deployforge -o jsonpath='{.spec.clusterIP}')
                        for i in 1 2 3 4 5; do
                            if kubectl run smoke-$RANDOM --rm -i --restart=Never \
                                 --image=curlimages/curl --quiet -- \
                                 curl -sf "http://${CIP}/actuator/health" | grep -q '"UP"'; then
                                echo "SMOKE PASS: app responded UP"
                                exit 0
                            fi
                            sleep 10
                        done
                        echo "SMOKE FAIL"
                        exit 1
EOF
                '''
            }
        }
    }

    // ------------------------------------------------------------
    // Post-pipeline: status summary in console + build description
    // ------------------------------------------------------------
    post {
        success {
            echo "============================================"
            echo " DeployForge build #${BUILD_NUMBER}: SUCCESS"
            echo " Image: ${FULL_IMAGE}"
            echo " Cluster: ${MASTER_HOST} (deployforge namespace)"
            echo "============================================"
        }
        failure {
            echo "============================================"
            echo " DeployForge build #${BUILD_NUMBER}: FAILED"
            echo " Check the failed stage above."
            echo "============================================"
        }
        always {
            // Tidy up stale Docker images on the Jenkins host
            sh 'docker image prune -f --filter "until=24h" || true'
        }
    }
}
