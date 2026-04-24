<h3 align="left">
  <img width="600" height="128" alt="image" src="https://raw.githubusercontent.com/artemis-env0/Packages/refs/heads/main/Images/Logo%20Pack/01%20Main%20Logo/Digital/SVG/envzero_logomark_fullcolor_rgb.svg" />
</h3>

---

# Terraform S3 Remote Backend with DynamoDB State Locking (env0)

A complete, working Terraform project that provisions an **AWS S3 remote backend** with **DynamoDB state locking**, deployed through **env0**. All resources live in `eu-central-1` (Frankfurt) and are configured to stay within or extremely close to the **AWS Free Tier**.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Repository Structure](#repository-structure)
3. [Cost Breakdown](#cost-breakdown)
4. [Prerequisites](#prerequisites)
5. [Step 1 — Bootstrap the Remote Backend (Local, Run Once)](#step-1--bootstrap-the-remote-backend-local-run-once)
6. [Step 2 — Configure the Infra Backend](#step-2--configure-the-infra-backend)
7. [Step 3 — Connect to env0](#step-3--connect-to-env0)
8. [Step 4 — Deploy via env0](#step-4--deploy-via-env0)
9. [Verifying the Remote Backend](#verifying-the-remote-backend)
10. [Viewing the State Lock](#viewing-the-state-lock)
11. [IAM Permissions](#iam-permissions)
12. [How State Locking Works](#how-state-locking-works)
13. [Why Two S3 Buckets?](#why-two-s3-buckets)
14. [Destroying Resources](#destroying-resources)
15. [Troubleshooting](#troubleshooting)
16. [Variable Reference](#variable-reference)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        env0 Platform                            │
│                                                                 │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │              Infra Environment (dev)                     │  │
│   │         Auto-deploys on push to main branch              │  │
│   └─────────────────────────┬────────────────────────────────┘  │
└─────────────────────────────┼───────────────────────────────────┘
                              │ terraform init + plan + apply
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     AWS  eu-central-1                           │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  S3 State Bucket (created by bootstrap — run once)       │   │
│  │  tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1       │   │
│  │                                                          │   │
│  │   infra/terraform.tfstate  ◄── written by env0 deploy    │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  DynamoDB Lock Table (created by bootstrap — run once)   │   │
│  │  tf-remote-backend-locks                                 │   │
│  │                                                          │   │
│  │   LockID written at start of plan/apply                  │   │
│  │   LockID deleted on completion                           │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Demo App Bucket (created by env0 infra deploy)          │   │
│  │  tf-remote-backend-demo-dev-<ACCOUNT_ID>                 │   │
│  │                                                          │   │
│  │   This is the "proof" workload resource                  │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Two-Layer Design

| Layer | Where it runs | Purpose |
|---|---|---|
| **bootstrap** | Locally, once | Creates the S3 state bucket and DynamoDB lock table |
| **infra** | env0, every deploy | Creates real workload resources; state stored in the bootstrap bucket |

The bootstrap layer must exist before the infra layer can initialise its remote backend. Bootstrap uses Terraform's default **local state** — there is no chicken-and-egg problem.

---

## Repository Structure

```
terraform-s3-remote-backend/
│
├── bootstrap/                   # Run locally ONCE to create the backend infrastructure
│   ├── providers.tf             # AWS provider + Terraform version constraint
│   ├── variables.tf             # Input variables (region, project_name, etc.)
│   ├── main.tf                  # S3 bucket + DynamoDB table resources
│   ├── outputs.tf               # Outputs including ready-to-use backend_hcl_snippet
│   └── terraform.tfstate        # Local state for bootstrap resources (committed to git)
│
├── infra/                       # Deployed by env0 on every push to main
│   ├── providers.tf             # AWS provider + Terraform version constraint
│   ├── backend.tf               # S3 backend block with hardcoded values
│   ├── backend.hcl              # Partial backend config (for local use)
│   ├── variables.tf             # Input variables (region, project_name, environment)
│   ├── main.tf                  # Demo S3 bucket (the proof workload)
│   └── outputs.tf               # Outputs including app_bucket_name
│
├── env0.yml                     # env0 custom workflow definition (version: 1)
├── iam-policy.json              # Minimum IAM policy for the Terraform IAM user
├── .gitignore                   # Excludes .terraform/, *.tfvars, etc.
└── README.md                    # This file
```

---

## Cost Breakdown

All costs assume light usage consistent with a proof-of-concept workload.

| Service | Resource | Expected Monthly Cost |
|---|---|---|
| S3 | State bucket (< 1 MB of state files) | **$0.00** (Free Tier: 5 GB free) |
| S3 | Demo app bucket (empty) | **$0.00** |
| S3 | PUT/GET requests (< 100/month) | **$0.00** (Free Tier: 2,000 PUT free) |
| DynamoDB | Lock table — PAY_PER_REQUEST | **< $0.01** (~2 ops per deploy) |
| DynamoDB | Storage (< 1 KB of lock items) | **$0.00** (Free Tier: 25 GB free) |
| **Total** | | **< $0.01 / month** |

> DynamoDB lock operations cost approximately $0.00000125 each. At 100 deploys/month that's $0.00025 — effectively zero.

---

## Prerequisites

### Local Tools

| Tool | Minimum Version | Install |
|---|---|---|
| Terraform CLI | 1.5.0+ | https://developer.hashicorp.com/terraform/install |
| AWS CLI | 2.x | https://aws.amazon.com/cli/ |
| Git | Any recent | https://git-scm.com |

### AWS Account

- An AWS account with access to `eu-central-1`
- An IAM user (e.g. `terraform-env0`) with the permissions in `iam-policy.json`
- AWS credentials configured locally via `aws configure`

### env0 Account

- A free env0 account at https://app.env0.com
- This Git repository connected to env0
- AWS credentials configured in env0 (see [Step 3](#step-3--connect-to-env0))

---

## Step 1 — Bootstrap the Remote Backend (Local, Run Once)

The bootstrap module creates the S3 bucket and DynamoDB table using **local state**. This only needs to be run once — ever.

### 1.1 — Configure AWS credentials

```bash
aws configure
# AWS Access Key ID: <your key>
# AWS Secret Access Key: <your secret>
# Default region name: eu-central-1
# Default output format: json
```

Verify credentials are working before proceeding:

```bash
aws sts get-caller-identity
```

You must see your account ID returned. If you get `InvalidClientTokenId`, your credentials are wrong — check they were copied correctly and that the key is Active in the AWS console.

> **Common gotcha:** If you previously ran `export AWS_ACCESS_KEY_ID=...` in the same terminal session, those environment variables override `~/.aws/credentials`. Run `unset AWS_ACCESS_KEY_ID && unset AWS_SECRET_ACCESS_KEY && unset AWS_SESSION_TOKEN` to clear them, then verify with `aws configure list` that the Type column shows `shared-credentials-file`.

### 1.2 — Navigate to the bootstrap directory

```bash
cd bootstrap/
```

### 1.3 — Initialise Terraform (local backend — no remote config needed yet)

```bash
terraform init
```

### 1.4 — Apply

```bash
terraform apply
```

When prompted for `state_bucket_name`, press Enter to accept the default — the bucket name is automatically derived from your project name, account ID, and region:

```
tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1
```

Or supply it explicitly:

```bash
terraform apply -var="state_bucket_name=$(aws sts get-caller-identity --query Account --output text)"
```

> **Note:** `state_bucket_name` is a legacy variable from an earlier version of this project. The actual bucket name is derived from `project_name`, `aws_region`, and your account ID inside `locals {}` in `main.tf`. You will not be prompted for it if it has a default set.

### 1.5 — Note the outputs

After a successful apply, note the `backend_hcl_snippet` output — it contains the exact bucket name and table name you need in Step 2.

```
dynamodb_table_name = "tf-remote-backend-locks"
state_bucket_name   = "tf-remote-backend-state-013141018419-eu-central-1"

backend_hcl_snippet = <<EOT
  bucket         = "tf-remote-backend-state-013141018419-eu-central-1"
  key            = "infra/terraform.tfstate"
  region         = "eu-central-1"
  dynamodb_table = "tf-remote-backend-locks"
  encrypt        = true
EOT
```

### 1.6 — Commit the bootstrap state to git

The bootstrap state file is committed to git so that the bootstrap resources are tracked. This is intentional and safe — it contains no secrets, only resource metadata.

```bash
git add -f terraform.tfstate
git add variables.tf
git commit -m "chore: bootstrap remote backend resources"
git push
```

---

## Step 2 — Configure the Infra Backend

The `infra/backend.tf` file contains the S3 backend block. It needs to point at the bucket and table created in Step 1.

Open `infra/backend.tf` and confirm the values match your bootstrap outputs:

```hcl
terraform {
  backend "s3" {
    bucket         = "tf-remote-backend-state-013141018419-eu-central-1"
    key            = "infra/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "tf-remote-backend-locks"
    encrypt        = true
  }
}
```

Replace `013141018419` with your actual AWS account ID if different. Then commit and push:

```bash
git add infra/backend.tf
git commit -m "chore: configure infra S3 backend with real bucket values"
git push
```

> **Why hardcode the values?** env0 runs `terraform init` without access to the local filesystem, so passing `-backend-config=backend.hcl` can be unreliable. Hardcoding in `backend.tf` is the most robust approach for CI/CD platforms.

---

## Step 3 — Connect to env0

### 3.1 — Create a Template

1. Log in to https://app.env0.com
2. Navigate to **Templates → New Template**
3. Select **GitHub** (or your VCS provider) and choose this repository
4. Set **Template Type** to **Terraform**
5. Set **Terraform Folder** to `infra`
6. Set **Branch** to `main`
7. Click through to **Variables** and add:

| Key | Value | Sensitive |
|---|---|---|
| `aws_region` | `eu-central-1` | Clear Text |
| `environment` | `dev` | Clear Text |
| `project_name` | `tf-remote-backend-demo` | Clear Text |

8. Complete the template creation wizard

### 3.2 — Add AWS Credentials

When creating the environment from the template (Step 4), you'll need to supply AWS credentials. The safest way is via environment variables set at the **Run Environment** screen:

| Key | Value | Sensitive |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | `AKIA...` | **Yes — Sensitive** |
| `AWS_SECRET_ACCESS_KEY` | your secret | **Yes — Sensitive** |

Always mark AWS credentials as **Sensitive** so they are encrypted and never appear in logs.

Alternatively, configure credentials at **Organisation Settings → Credentials → Add Credentials → AWS Access Keys** and select them when creating the environment.

---

## Step 4 — Deploy via env0

### 4.1 — Create a New Environment from the Template

1. Open your template in env0
2. Click **New Environment**
3. Set Environment Name: `dev`
4. Set Workspace Name: `dev`
5. Disable **Destroy in X hours** (set to Never) to prevent auto-teardown
6. Add AWS credentials in the Environment Variables section (see Step 3.2)
7. Click **Run**

### 4.2 — Approve the Plan

env0 runs `terraform plan` first and shows you a diff. Review it — you should see:

```
+ aws_s3_bucket.app
+ aws_s3_bucket_versioning.app
+ aws_s3_bucket_server_side_encryption_configuration.app
+ aws_s3_bucket_public_access_block.app

Plan: 4 to add, 0 to change, 0 to destroy.
```

Click **Approve** to apply.

### 4.3 — Verify in AWS Console

After a successful apply, you should have:

| Resource | Name |
|---|---|
| S3 state bucket | `tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1` |
| S3 demo bucket | `tf-remote-backend-demo-dev-<ACCOUNT_ID>` |
| DynamoDB table | `tf-remote-backend-locks` |

---

## Verifying the Remote Backend

After a successful env0 deploy, confirm the state file was written remotely:

**In the AWS Console:**
1. Go to S3 → `tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1`
2. You should see a folder `infra/`
3. Inside it: `terraform.tfstate`

**Via CLI:**
```bash
aws s3 ls s3://tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1/infra/ --region eu-central-1
```

Expected output:
```
2026-04-23 21:24:31       2847 terraform.tfstate
```

If the file is there — the full system is working end to end. ✅

---

## Viewing the State Lock

The DynamoDB lock only exists for a **few seconds during an active plan or apply**. It is written at the start and deleted on completion. To catch it:

**1. Open DynamoDB in a browser tab:**
AWS Console → DynamoDB → Tables → `tf-remote-backend-locks` → **Explore table items**

**2. Trigger a redeploy in env0** (click Redeploy)

**3. Immediately switch to DynamoDB and click Scan/Run**

You should briefly see a row like:
```json
{
  "LockID": "tf-remote-backend-state-.../infra/terraform.tfstate",
  "Info": "{\"Operation\":\"OperationTypePlan\",\"Who\":\"env0-runner@...\"}"
}
```

**After the deploy completes**, the table will be empty — this is correct. An empty table means the lock was properly acquired and released.

> If a lock row persists after a deploy fails, Terraform will refuse to run until it's cleared. See [Troubleshooting](#troubleshooting) for how to force-unlock.

---

## IAM Permissions

The `iam-policy.json` file contains the minimum IAM permissions required. Key permissions explained:

| Permission | Why needed |
|---|---|
| `s3:GetObject` / `s3:PutObject` | Read and write the state file |
| `s3:ListBucket` | Check if the state file exists |
| `dynamodb:GetItem` / `PutItem` / `DeleteItem` | Acquire and release state locks |
| `dynamodb:DescribeTable` | Verify the lock table is active |
| `dynamodb:DescribeTimeToLive` | Required by the AWS provider when reading DynamoDB table state |
| `s3:GetBucketPolicy` | Required by the AWS provider when reading S3 bucket state |
| `sts:GetCallerIdentity` | Used by `data.aws_caller_identity.current` in Terraform |

> **For initial setup:** The easiest approach is to attach `AdministratorAccess` to your IAM user while bootstrapping. Once everything is working, replace it with the minimal policy from `iam-policy.json`.

---

## How State Locking Works

```
terraform plan / apply
        │
        ▼
1. ACQUIRE LOCK
   DynamoDB PutItem → LockID: "bucket/infra/terraform.tfstate"
        │
        ▼
2. FETCH CURRENT STATE
   S3 GetObject → infra/terraform.tfstate
        │
        ▼
3. CALCULATE DIFF / APPLY CHANGES
        │
        ▼
4. WRITE NEW STATE
   S3 PutObject → infra/terraform.tfstate (new version created)
        │
        ▼
5. RELEASE LOCK
   DynamoDB DeleteItem → removes the lock row
```

If a second `terraform apply` runs concurrently, it reads the existing lock and fails with:

```
Error: Error locking state: ConditionalCheckFailedException
Lock Info:
  ID:        abc-123
  Operation: OperationTypeApply
  Who:       env0-runner@worker-1
```

This prevents two deploys from corrupting the state file simultaneously.

---

## Why Two S3 Buckets?

After a successful deploy you'll have two buckets. Here's why they're separate:

| Bucket | Purpose |
|---|---|
| `tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1` | **The filing cabinet** — stores Terraform state files. Infrastructure for Terraform itself. |
| `tf-remote-backend-demo-dev-<ACCOUNT_ID>` | **The workload** — the actual resource env0 deployed. In a real project this would hold application data. |

**Why not use the same bucket for both?**

1. **Circular dependency** — Terraform needs the state bucket to exist before it runs. If Terraform also manages that bucket, you get a chicken-and-egg problem. Running `terraform destroy` would try to delete the bucket containing its own state mid-operation.

2. **Accidental deletion** — `terraform destroy` on the workload would wipe the state file too. Separate buckets with `prevent_destroy = true` on the state bucket prevent this.

3. **Access control** — In real teams, the state bucket needs tighter permissions than application buckets. Mixing them makes IAM policies messy.

4. **Clarity** — At a glance, `*-state-*` = Terraform internals; everything else = real workloads.

In production you'd reuse the **one state bucket** across many projects, each with a different `key` path:
```
s3://tf-remote-backend-state-.../
  ├── infra/terraform.tfstate          ← this project
  ├── another-project/terraform.tfstate
  └── yet-another/terraform.tfstate
```

---

## Destroying Resources

### Destroy the infra workload (demo S3 bucket)

In env0, click **Destroy** on the `dev` environment. Or locally:

```bash
cd infra/
terraform init
terraform destroy
```

### Destroy the bootstrap resources

> ⚠️ **Warning:** Destroying the state bucket deletes all Terraform state files. Ensure all workspaces using this backend have been destroyed first.

The `prevent_destroy` lifecycle block must be commented out before you can destroy:

```bash
cd bootstrap/
# Edit main.tf — comment out the lifecycle { prevent_destroy = true } block
terraform destroy
```

---

## Troubleshooting

### `InvalidClientTokenId` — credentials rejected by AWS

Your AWS credentials are invalid or stale.

```bash
# Check what credentials are actually being used
aws configure list

# If Type shows "env" — environment variables are overriding your config file
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

# Verify
aws sts get-caller-identity
```

If the key was just created in the AWS console, wait 30–60 seconds for IAM propagation then retry.

---

### `BucketAlreadyOwnedByYou` during bootstrap

The S3 bucket already exists in your account from a previous run. This means bootstrap already succeeded. You don't need to run it again — just proceed to deploying the infra workspace.

---

### `Error: required field is not set` for backend during `terraform init`

The `infra/backend.tf` still has placeholder values. Open it and replace with your actual bucket name and account ID.

---

### `Instance cannot be destroyed` — prevent_destroy error

The `prevent_destroy = true` lifecycle block is blocking a plan that includes destroying the S3 bucket. This is the safety net working correctly. If you genuinely want to destroy, comment out the lifecycle block in `bootstrap/main.tf` first.

---

### State lock not released after a failed deploy

Find the lock ID from the error output and force-unlock:

```bash
cd infra/
terraform force-unlock <LOCK_ID>
```

Or delete directly from DynamoDB:

```bash
aws dynamodb delete-item \
  --table-name tf-remote-backend-locks \
  --key '{"LockID": {"S": "tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1/infra/terraform.tfstate"}}' \
  --region eu-central-1
```

---

### env0 YAML validation error — `instance is not allowed to have the additional property "environments"`

The `env0.yml` file must use `version: 1` at the top. The `environments:` key is **not** valid in env0's deploy spec schema — environments are configured in the env0 UI, not in this file.

The `env0.yml` in this repo is intentionally minimal and only defines custom workflow steps.

---

## Variable Reference

### Bootstrap (`bootstrap/variables.tf`)

| Variable | Type | Default | Description |
|---|---|---|---|
| `aws_region` | string | `eu-central-1` | AWS region for backend resources |
| `project_name` | string | `tf-remote-backend` | Used as prefix for bucket and table names |
| `state_key_prefix` | string | `""` | Optional prefix inside the S3 bucket for state files |

Bucket name is derived automatically as: `${project_name}-state-${account_id}-${region}`
Table name is derived automatically as: `${project_name}-locks`

### Infra (`infra/variables.tf`)

| Variable | Type | Default | Description |
|---|---|---|---|
| `aws_region` | string | `eu-central-1` | AWS region for workload resources |
| `project_name` | string | `tf-remote-backend-demo` | Used for naming the demo bucket |
| `environment` | string | `dev` | One of: `dev`, `staging`, `prod` |

Demo bucket name is derived as: `${project_name}-${environment}-${account_id}`

---

## Quick Reference — Commands

```bash
# ── AWS auth check ────────────────────────────────────────────────────────────
aws sts get-caller-identity

# ── Bootstrap (run once locally) ─────────────────────────────────────────────
cd bootstrap/
terraform init
terraform apply
git add -f terraform.tfstate && git commit -m "chore: bootstrap" && git push

# ── Local infra deploy (optional — env0 handles this normally) ────────────────
cd infra/
terraform init
terraform plan
terraform apply

# ── Verify state was stored remotely ─────────────────────────────────────────
aws s3 ls s3://tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1/infra/ --region eu-central-1

# ── Check lock table (should be empty between deploys) ───────────────────────
aws dynamodb scan --table-name tf-remote-backend-locks --region eu-central-1 --query "Count"

# ── Force-unlock a stuck state lock ──────────────────────────────────────────
cd infra/
terraform force-unlock <LOCK_ID>
```
