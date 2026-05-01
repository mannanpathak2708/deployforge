# Terraform — First-Time Guide

You've never used Terraform. That's fine. Reading this once will put you ahead of half the people in your viva.

## What Terraform actually is

Terraform reads `.tf` files (your "desired state") and figures out the API calls needed to make AWS match. Run `terraform apply` once and you get the infrastructure. Edit a file and run `apply` again, and Terraform diffs the new desired state against what's actually deployed and only changes the difference.

The core concepts you need to know:

| Term | What it means |
|---|---|
| **Provider** | A plugin that knows how to talk to one platform's API. We use the `aws` provider. |
| **Resource** | A thing Terraform manages — `aws_instance`, `aws_vpc`, etc. |
| **Data source** | A read-only lookup — e.g. "find the latest Ubuntu AMI". |
| **Variable** | An input value (like `my_public_ip`). Defined in `variables.tf`, set in `terraform.tfvars`. |
| **Output** | A value Terraform prints after apply (like the master's public IP). |
| **State** | A JSON file (`terraform.tfstate`) that maps your `.tf` files to real AWS resources. **Never delete this**, never commit it. |
| **Plan** | A preview of what apply *would* do. Always plan before applying. |

## The 4 commands you'll run

```bash
terraform init       # one time per project — downloads the AWS provider plugin
terraform plan       # preview changes (free, makes no real changes)
terraform apply      # actually create/update resources in AWS
terraform destroy    # delete everything Terraform created
```

The Makefile in this directory wraps these as `make init`, `make plan`, `make apply`, `make destroy` so you don't have to remember.

## What happens on first apply (full walkthrough)

```bash
cd terraform/
make init
```

You'll see Terraform download the AWS provider (~5 seconds). It creates a `.terraform/` directory and a `.terraform.lock.hcl` file. Both are gitignored.

```bash
make plan
```

Terraform will:
1. Read all `.tf` files
2. Read your `terraform.tfvars`
3. Call AWS APIs to fetch *current* state (this is where it learns there's nothing yet)
4. Compute the diff and print every single resource it will create

You should see something like `Plan: 19 to add, 0 to change, 0 to destroy.`

**Read the plan output.** Look for things ending with `~` (modify) or `-` (destroy) — on a first apply there should be none of those, only `+` (create). If you see destroys on a first apply, stop and check what's happening.

```bash
make apply
```

Terraform asks "Do you want to perform these actions?" Type `yes` and press Enter. Then it spends 5–10 minutes calling AWS APIs:

- VPC, IGW, subnets, route tables: ~30 seconds
- Security groups, IAM role, ECR repo: ~30 seconds
- EC2 instances: ~3-5 minutes (this dominates the wall time)

When it finishes you'll see all the outputs printed at the bottom:

```
Outputs:

aws_account_id = "560205084884"
ecr_repository_url = "560205084884.dkr.ecr.us-east-1.amazonaws.com/deployforge/taskmanager"
master_public_ip = "44.x.x.x"
ssh_master = "ssh -i ~/.ssh/deployforge-key.pem ubuntu@44.x.x.x"
worker_public_ips = ["3.x.x.x", "54.x.x.x"]
...
```

## Verify the cluster is up

```bash
# SSH to the master (use the printed command, or)
make ssh-master

# Once on the master, check it has internet and Python
ubuntu@deployforge-master$ python3 --version
ubuntu@deployforge-master$ curl -sI https://google.com | head -1

# exit back to your laptop
exit
```

If you can SSH in and Python responds, you're golden — Stage 3 (Ansible) will do the kubeadm install from here.

## What to do if `apply` fails partway

Don't panic, don't manually delete things in the AWS Console. Just:

```bash
terraform plan
```

This re-reads state and tells you what's still needed. Then `terraform apply` again — Terraform is **idempotent**, it will only create what's missing.

If a resource is genuinely stuck (rare but happens with security groups), `terraform destroy` and start over. The state file knows what to delete.

## How to read the state file (don't edit it)

```bash
make state-list
# prints every resource Terraform is managing

terraform state show aws_instance.master
# detailed view of one resource
```

If you ever need to remove something from state (e.g. you manually deleted it in the Console and Terraform is confused), use `terraform state rm`. **Never edit `terraform.tfstate` by hand.**

## Cost discipline (read this before you walk away from your laptop)

Running cost: **~$3.30/day** (3 × t3.medium + EBS).

Whenever you stop working for the day, run `make destroy`. The whole cluster goes away in ~3 minutes. State file remembers what was there — next morning, `make apply` rebuilds an identical cluster in 5 minutes. The ECR images persist (separate resource), but EBS data on the EC2s does not.

```bash
# End of session
make destroy
# Type 'destroy' to confirm

# Next session
make apply
```

If you forget and leave it running for a week, that's $25. Annoying but not catastrophic. If you forget for a month, $100. Set a calendar reminder. Or use AWS Budgets — Console → Billing → Budgets → set $20/month alert.

## What Terraform does NOT do

- It doesn't install kubeadm. That's Ansible (Stage 3).
- It doesn't deploy your app. That's `kubectl` / GitHub Actions (Stages 1, 4).
- It doesn't manage your local Mac, GitHub, or anything outside AWS.

Each tool has one job. Stage 2 is "AWS infra exists." Stage 3 is "the AWS infra runs Kubernetes." Stage 4 is "Kubernetes runs your app."

## Common errors and fixes

| Error | Cause | Fix |
|---|---|---|
| `Error: error configuring Terraform AWS Provider: no valid credential` | AWS CLI not configured | Run `aws configure` |
| `InvalidKeyPair.NotFound` | Key pair doesn't exist in the chosen region | Check region in `terraform.tfvars` matches where you created the key |
| `UnauthorizedOperation` | IAM user missing permissions | Use root for now (you said you would) or attach `AdministratorAccess` |
| `Error: timeout while waiting for state` | EC2 instance limit hit | Request quota increase in AWS Console, or reduce `worker_count` |
| Plan shows changes I didn't make | AMI updated upstream | Already ignored via `lifecycle.ignore_changes` |
| `vpcLimitExceeded` | You already have 5 VPCs in this region | Delete unused VPCs in AWS Console first |

## Files in this directory — what each one does

| File | Purpose |
|---|---|
| `main.tf` | Provider config, version pinning, AMI lookup |
| `variables.tf` | Input variable declarations + validation |
| `terraform.tfvars` | Your specific values (gitignored, copy from `.example`) |
| `terraform.tfvars.example` | Template (committed) |
| `vpc.tf` | VPC, subnets, IGW, route tables |
| `security_groups.tf` | All three SGs and cross-SG rules |
| `iam.tf` | EC2 role for ECR pull |
| `ecr.tf` | Container registry |
| `ec2.tf` | The 3 instances |
| `outputs.tf` | Values printed after apply |
| `Makefile` | Shortcut commands |
| `terraform.tfstate` | **Auto-generated, gitignored, do not touch** |
| `.terraform/` | **Auto-generated provider plugins, gitignored** |

## For the report

Take screenshots of:
1. `terraform plan` output (the "19 to add" line)
2. `terraform apply` output (the resources being created in real time)
3. The Outputs block at the end of apply
4. AWS Console → EC2 → Instances showing all 3 nodes Running
5. AWS Console → VPC → Your VPCs showing `deployforge-vpc`
6. `terraform state list` output

These are direct evidence for Chapter 6 (Implementation) Section 6.5 (Deployment Process).
