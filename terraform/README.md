# DeployForge — Stage 2 of 4

**Terraform: AWS VPC, EC2 cluster nodes, ECR, IAM, security groups**

This stage provisions every AWS resource Stages 3–4 will need. Read [TERRAFORM_GUIDE.md](TERRAFORM_GUIDE.md) first if this is your first Terraform project — it covers concepts, state, the four core commands, and how to read failures.

## What this creates

| Resource | Count | Purpose |
|---|---|---|
| VPC `10.0.0.0/16` | 1 | Network boundary |
| Public subnet | 2 | One per AZ (us-east-1a, us-east-1b) |
| Internet Gateway | 1 | Outbound internet access |
| Route table | 1 | Routes 0.0.0.0/0 → IGW |
| Security group `ssh` | 1 | Port 22 from your IP only |
| Security group `k8s-control-plane` | 1 | API server + etcd + kubelet ports |
| Security group `k8s-worker` | 1 | Kubelet + NodePort range |
| IAM role + instance profile | 1 | EC2 → ECR pull permission |
| ECR repository | 1 | `deployforge/taskmanager` |
| EC2 instance (master) | 1 | `t3.medium`, Ubuntu 22.04, 30 GB gp3 |
| EC2 instance (worker) | 2 | `t3.medium`, Ubuntu 22.04, 30 GB gp3 |

**Total:** ~19 resources. Apply takes 5–10 minutes (EC2 creation dominates).

## Cost

```
3 × t3.medium     × $0.0416/hr = $0.125/hr
3 × 30 GB gp3     × $0.08/GB-mo prorated = ~$0.01/hr
1 × ECR storage   = ~$0.001/hr
Data transfer     = negligible
                                ─────────
Total ≈ $0.14/hr ≈ $3.30/day if left running
```

Run `make destroy` when you're done for the day. Nightly destroy/morning apply works fine and keeps total project cost in the $5–10 range.

## How to deploy

```bash
# From inside the terraform/ directory
cd terraform/

# 1. First run only — copies tfvars and downloads providers
make init

# 2. (Optional) re-confirm your public IP if you've moved networks
curl -s https://checkip.amazonaws.com
# If it changed, edit terraform.tfvars and update my_public_ip

# 3. Preview — read what's about to happen
make plan

# 4. Apply — actually create resources (5-10 min)
make apply

# 5. Verify SSH works
make ssh-master
# you should land on the master, type `exit` to come back

# 6. Generate Ansible inventory for Stage 3
make inventory
# writes ../ansible/inventory.ini using real public IPs

# At end of session
make destroy
# type 'destroy' when prompted
```

## Files

```
terraform/
├── main.tf                       Provider, version pinning, AMI lookup
├── variables.tf                  Input variables with validation
├── terraform.tfvars.example      Template — values pre-filled for you
├── vpc.tf                        VPC + subnets + IGW + route table
├── security_groups.tf            Three SGs with kubeadm port lists
├── iam.tf                        EC2 role + instance profile for ECR pull
├── ecr.tf                        Container registry + lifecycle policy
├── ec2.tf                        Master + workers
├── outputs.tf                    IPs, ECR URL, ready-made SSH commands
├── Makefile                      `make plan/apply/destroy/ssh-master`
└── TERRAFORM_GUIDE.md            First-timer's walkthrough
```

## Key design decisions (for the report and viva)

| Decision | Why |
|---|---|
| **Public subnets, no NAT Gateway** | NAT costs $32/mo even idle. SGs lock down access by IP. |
| **Per-role security groups** | Least privilege: workers can't accept etcd traffic, master can't accept NodePorts from internet. |
| **IMDSv2 required (`http_tokens = required`)** | Prevents SSRF attacks on the EC2 metadata service — CIS recommendation. |
| **Encrypted EBS volumes** | AES256 at rest, free, no reason not to. |
| **`ignore_changes = [ami]`** | New Ubuntu point releases shouldn't recreate cluster nodes. |
| **`lifecycle.ignore_changes` instead of `prevent_destroy`** | We *do* want `terraform destroy` to work; we just don't want incidental AMI updates to recreate the master. |
| **Dynamic AMI lookup** | Hardcoded AMI IDs go stale within months. The `data.aws_ami.ubuntu_2204` block always finds the latest. |
| **ECR lifecycle policy** | Auto-expires old images. Without it you'll be paying storage on dead `latest` images forever. |
| **Default tags via provider** | Cost Explorer can group everything tagged `Project=deployforge` for accurate per-project billing. |

## What this stage does NOT do

- **Does not install kubeadm/Docker/kubelet on the EC2s.** That's Stage 3 (Ansible).
- **Does not deploy the app.** Stage 4 (CI/CD).
- **Does not configure DNS.** Use the master's public IP directly, or set up Route53 manually if you want a domain.
- **Does not create an S3 bucket for Terraform state.** State stays local. Fine for a one-person course project; switch to S3+DynamoDB backend for team work.

## After successful apply, you'll have

- 3 EC2 instances visible in AWS Console → EC2
- 1 VPC visible in AWS Console → VPC
- 1 ECR repo visible in AWS Console → ECR
- Working SSH from your Mac → master and workers
- A printable list of IPs that Stage 3 will consume

## Next: Stage 3

Stage 3 (Ansible) takes the 3 bare Ubuntu EC2s and turns them into a working kubeadm cluster: containerd, kubeadm, kubelet, kubectl, Calico CNI, NGINX Ingress, kube-prometheus-stack. Then `kubectl apply -k k8s/base` deploys the app from Stage 1.

Hand off from Stage 2 → Stage 3 happens through `ansible/inventory.ini`, generated by `make inventory` from the Terraform outputs.
