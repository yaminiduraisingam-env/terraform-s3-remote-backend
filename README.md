<h3 align="left">
  <img width="600" height="128" alt="image" src="https://raw.githubusercontent.com/artemis-env0/Packages/refs/heads/main/Images/Logo%20Pack/01%20Main%20Logo/Digital/SVG/envzero_logomark_fullcolor_rgb.svg" />
</h3>

---

# Terraform S3 Remote Backend with DynamoDB State Locking (env0)

A complete, working Terraform project that provisions an **AWS S3 remote backend** with **DynamoDB state locking**, deployed entirely through **env0**. All resources live in `eu-central-1` (Frankfurt) and are configured to stay within or extremely close to the **AWS Free Tier**.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Repository Structure](#repository-structure)
3. [Cost Breakdown](#cost-breakdown)
4. [Prerequisites](#prerequisites)
5. [End-to-End Deployment via env0](#end-to-end-deployment-via-env0)
   - [Phase 1 — AWS Credentials](#phase-1--aws-credentials)
   - [Phase 2 — Create the Bootstrap Template](#phase-2--create-the-bootstrap-template)
   - [Phase 3 — Deploy Bootstrap via env0](#phase-3--deploy-bootstrap-via-env0)
   - [Phase 4 — Configure the Infra Backend](#phase-4--configure-the-infra-backend)
   - [Phase 5 — Create the Infra Template](#phase-5--create-the-infra-template)
   - [Phase 6 — Deploy Infra via env0](#phase-6--deploy-infra-via-env0)
6. [Verifying the Remote Backend](#verifying-the-remote-backend)
7. [Viewing the State Lock](#viewing-the-state-lock)
8. [IAM Permissions](#iam-permissions)
9. [How State Locking Works](#how-state-locking-works)
10. [Why Two S3 Buckets?](#why-two-s3-buckets)
11. [Destroying Resources](#destroying-resources)
12. [Troubleshooting](#troubleshooting)
13. [Variable Reference](#variable-reference)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                           env0 Platform                              │
│                                                                      │
│  ┌─────────────────────────┐    ┌─────────────────────────────────┐  │
│  │  Bootstrap Environment  │    │      Infra Environment (dev)    │  │
│  │  Run ONCE to create     │    │  Auto-deploys on push to main   │  │
│  │  state bucket + table   │    │  State stored in state bucket   │  │
│  └────────────┬────────────┘    └──────────────┬──────────────────┘  │
└───────────────┼─────────────────────────────────┼────────────────────┘
                │ terraform apply                  │ terraform init + apply
                ▼                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                        AWS  eu-central-1                             │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  S3 State Bucket          ◄── created by bootstrap             │  │
│  │  tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1             │  │
│  │                                                                │  │
│  │   env:/<workspace>/infra/terraform.tfstate  ◄── written by     │  │
│  │                                                  env0 deploy   │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  DynamoDB Lock Table      ◄── created by bootstrap             │  │
│  │  tf-remote-backend-locks                                       │  │
│  │                                                                │  │
│  │   LockID written at start of plan/apply                        │  │
│  │   LockID deleted on completion                                 │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  Demo App Bucket          ◄── created by infra deploy          │  │
│  │  tf-remote-backend-demo-dev-<ACCOUNT_ID>                       │  │
│  │                                                                │  │
│  │   This is the "proof" workload resource                        │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

### Two-Layer Design

| Layer | Where it runs | Purpose |
|---|---|---|
| **bootstrap** | env0, run once | Creates the S3 state bucket and DynamoDB lock table |
| **infra** | env0, every deploy | Creates workload resources; state stored in the bootstrap bucket |

The bootstrap layer must be deployed first. Its state is managed by env0 internally. Once bootstrap succeeds, the infra layer can initialise its remote backend.

---

## Repository Structure

```
terraform-s3-remote-backend/
│
├── bootstrap/                   # Deployed ONCE via env0 to create backend infrastructure
│   ├── providers.tf             # AWS provider + Terraform version constraint
│   ├── variables.tf             # Input variables (region, project_name, etc.)
│   ├── main.tf                  # S3 bucket + DynamoDB table resources
│   └── outputs.tf               # Outputs including ready-to-use backend_hcl_snippet
│
├── infra/                       # Deployed by env0 on every push to main
│   ├── providers.tf             # AWS provider + Terraform version constraint
│   ├── backend.tf               # S3 backend block — updated after bootstrap deploys
│   ├── backend.hcl              # Partial backend config reference (documentation only)
│   ├── variables.tf             # Input variables (region, project_name, environment)
│   ├── main.tf                  # Demo S3 bucket (the proof workload)
│   └── outputs.tf               # Outputs including app_bucket_name
│
├── iam-policy.json              # Minimum IAM policy for the Terraform IAM user
└── README.md                    # This file
```

---

## Cost Breakdown

| Service | Resource | Expected Monthly Cost |
|---|---|---|
| S3 | State bucket (< 1 MB of state files) | **$0.00** (Free Tier: 5 GB free) |
| S3 | Demo app bucket (empty) | **$0.00** |
| S3 | PUT/GET requests (< 100/month) | **$0.00** (Free Tier: 2,000 PUT free) |
| DynamoDB | Lock table — PAY_PER_REQUEST | **< $0.01** (~2 ops per deploy) |
| DynamoDB | Storage (< 1 KB of lock items) | **$0.00** (Free Tier: 25 GB free) |
| **Total** | | **< $0.01 / month** |

> DynamoDB lock operations cost approximately $0.00000125 each. At 100 deploys/month that is $0.00025 — effectively zero.

---

## Prerequisites

### Local Tools

| Tool | Minimum Version | Install |
|---|---|---|
| Terraform CLI | 1.5.0+ | https://developer.hashicorp.com/terraform/install |
| AWS CLI | 2.x | https://aws.amazon.com/cli/ |
| Git | Any recent | https://git-scm.com |

### Accounts

- An AWS account with access to `eu-central-1`
- An IAM user (e.g. `terraform-env0`) with `AdministratorAccess` attached (can be tightened to `iam-policy.json` after everything works)
- A free env0 account at https://app.env0.com
- This repository pushed to GitHub (or GitLab / Bitbucket)

---

## End-to-End Deployment via env0

Everything from this point is done through the **env0 UI** and **AWS Console** — no local Terraform commands needed.

---

### Phase 1 — AWS Credentials

Before creating any templates, store your AWS credentials securely in env0 so both environments can use them.

1. In env0, click **Organisation Settings** (bottom-left) → **Credentials**
2. Click **+ Add Credentials** → select **AWS Access Keys**
3. Enter your IAM user's Access Key ID and Secret Access Key
4. Name it `aws-eu-central-1`
5. Click **Save**

> Keep AWS credentials out of plain-text Terraform Variables. Always use the Credentials store so they are encrypted and never appear in deployment logs.

---

### Phase 2 — Create the Bootstrap Template

The bootstrap template tells env0 how to deploy the `bootstrap/` folder.

1. In env0, navigate to your **Project → Templates → New Template**
2. Select **Terraform** as the template type
3. Connect to **GitHub** and select this repository
4. Set **Branch** to `main`
5. Set **Terraform Folder** to `bootstrap`
6. On the **Variables** screen, add:

| Key | Value | Sensitive |
|---|---|---|
| `aws_region` | `eu-central-1` | Clear Text |
| `project_name` | `tf-remote-backend` | Clear Text |

7. Name the template `terraform-s3-remote-backend-bootstrap`
8. Complete the wizard and save

---

### Phase 3 — Deploy Bootstrap via env0

1. Open the bootstrap template → click **New Environment**
2. Set **Environment Name** to `bootstrap`
3. Set **Workspace Name** to `bootstrap`
4. Scroll to **Environment Variables** and add:

| Key | Value | Sensitive |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | your key ID | **Yes — Sensitive** |
| `AWS_SECRET_ACCESS_KEY` | your secret | **Yes — Sensitive** |

5. Turn off **Destroy in X hours** — set to Never
6. Click **Run**

env0 runs `terraform init` → `terraform plan`. Review the plan — you should see:

```
+ aws_dynamodb_table.terraform_locks
+ aws_s3_bucket.terraform_state
+ aws_s3_bucket_lifecycle_configuration.terraform_state
+ aws_s3_bucket_public_access_block.terraform_state
+ aws_s3_bucket_server_side_encryption_configuration.terraform_state
+ aws_s3_bucket_versioning.terraform_state

Plan: 6 to add, 0 to change, 0 to destroy.
```

Click **Approve**. After the apply completes, open the **Resources** tab and note:

- `state_bucket_name` — e.g. `tf-remote-backend-state-013141018419-eu-central-1`
- `dynamodb_table_name` — e.g. `tf-remote-backend-locks`

You need both values in the next phase.

---

### Phase 4 — Configure the Infra Backend

Now that the S3 bucket and DynamoDB table exist, update `infra/backend.tf` with the real values from the bootstrap outputs.

Open `infra/backend.tf` in your editor and update the backend block:

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

Replace `013141018419` with your actual AWS account ID from the bootstrap output. Commit and push to `main`:

```bash
git add infra/backend.tf
git commit -m "chore: configure infra backend with bootstrap outputs"
git push
```

> **Why hardcode the values?** env0 runs `terraform init` in an isolated runner. Hardcoding directly in `backend.tf` is the most reliable approach for CI/CD platforms and avoids init argument complexity.

---

### Phase 5 — Create the Infra Template

1. In env0, navigate to your **Project → Templates → New Template**
2. Select **Terraform**
3. Connect to the same GitHub repository
4. Set **Branch** to `main`
5. Set **Terraform Folder** to `infra`
6. On the **Variables** screen, add:

| Key | Value | Sensitive |
|---|---|---|
| `aws_region` | `eu-central-1` | Clear Text |
| `environment` | `dev` | Clear Text |
| `project_name` | `tf-remote-backend-demo` | Clear Text |

7. Name the template `terraform-s3-remote-backend-infra`
8. Complete the wizard and save

---

### Phase 6 — Deploy Infra via env0

1. Open the infra template → click **New Environment**
2. Set **Environment Name** to `dev`
3. Set **Workspace Name** to `dev`
4. Add AWS credentials in **Environment Variables** (same as Phase 3 Step 4)
5. Turn off **Destroy in X hours** — set to Never
6. Click **Run**

env0 initialises against the S3 backend, then plans. You should see:

```
+ aws_s3_bucket.app
+ aws_s3_bucket_versioning.app
+ aws_s3_bucket_server_side_encryption_configuration.app
+ aws_s3_bucket_public_access_block.app

Plan: 4 to add, 0 to change, 0 to destroy.
```

Click **Approve**. After the apply completes you will have:

| Resource | Name |
|---|---|
| S3 state bucket | `tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1` |
| DynamoDB lock table | `tf-remote-backend-locks` |
| S3 demo bucket | `tf-remote-backend-demo-dev-<ACCOUNT_ID>` |

---

## Verifying the Remote Backend

After the infra deploy, confirm the state file was written to S3.

**In the AWS Console:**
1. Go to S3 → `tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1`
2. You will see a folder prefixed with `env:/` — this is env0's workspace namespace
3. Navigate into it → `infra/` → `terraform.tfstate`

**Via CLI:**
```bash
aws s3 ls s3://tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1/ --recursive --region eu-central-1
```

Expected output:
```
2026-04-24 10:22:27   6702   env:/<workspace>/infra/terraform.tfstate
```

> env0 automatically namespaces state under `env:/<workspace-id>/` so multiple environments sharing the same bucket never collide with each other.

If the file is there, the full system is working end to end. ✅

---

## Viewing the State Lock

The DynamoDB lock only exists for a **few seconds during an active plan or apply**. To catch it live:

**1. Open two browser tabs:**
- Tab 1: env0 infra environment → click **Redeploy**
- Tab 2: AWS Console → DynamoDB → `tf-remote-backend-locks` → **Explore table items**

**2. The moment env0 starts the plan — click Scan in DynamoDB**

You should briefly see:
```json
{
  "LockID": "tf-remote-backend-state-.../infra/terraform.tfstate",
  "Info": "{\"Operation\":\"OperationTypePlan\",\"Who\":\"env0-runner@...\"}"
}
```

**After the deploy completes** the table will be empty — this is the correct healthy state. An empty table proves the lock was properly acquired and released.

> If a lock row persists after a failed deploy, Terraform will refuse future runs until it is cleared. See [Troubleshooting](#troubleshooting) for how to force-unlock.

---

## IAM Permissions

The `iam-policy.json` file contains the minimum permissions required. Key actions explained:

| Permission | Why needed |
|---|---|
| `s3:GetObject` / `s3:PutObject` | Read and write the state file |
| `s3:ListBucket` | Check if the state file exists |
| `dynamodb:GetItem` / `PutItem` / `DeleteItem` | Acquire and release state locks |
| `dynamodb:DescribeTable` | Verify the lock table is active |
| `dynamodb:DescribeTimeToLive` | Required by the AWS provider when reading DynamoDB state |
| `s3:GetBucketPolicy` | Required by the AWS provider when reading S3 bucket state |
| `sts:GetCallerIdentity` | Used by `data.aws_caller_identity.current` in Terraform |

> Start with `AdministratorAccess` to avoid permission issues during initial setup. Replace with the minimal `iam-policy.json` policy once everything is working.

---

## How State Locking Works

```
env0 triggers terraform plan / apply
        │
        ▼
1. ACQUIRE LOCK
   DynamoDB PutItem → LockID: "bucket/.../infra/terraform.tfstate"
        │
        ▼
2. FETCH CURRENT STATE
   S3 GetObject → env:/<workspace>/infra/terraform.tfstate
        │
        ▼
3. CALCULATE DIFF / APPLY CHANGES
        │
        ▼
4. WRITE NEW STATE
   S3 PutObject → new version of terraform.tfstate created
        │
        ▼
5. RELEASE LOCK
   DynamoDB DeleteItem → lock row removed
```

If two deploys run simultaneously, the second one fails immediately with:

```
Error: Error locking state: ConditionalCheckFailedException
Lock Info:
  ID:        abc-123
  Operation: OperationTypeApply
  Who:       env0-runner@worker-1
```

This prevents concurrent deploys from corrupting the state file.

---

## Why Two S3 Buckets?

After a successful deploy you will have two buckets. Here is why they are separate:

| Bucket | Purpose |
|---|---|
| `tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1` | **The filing cabinet** — stores Terraform state files. Infrastructure for Terraform itself. |
| `tf-remote-backend-demo-dev-<ACCOUNT_ID>` | **The workload** — the actual resource env0 deployed. In a real project this would hold application data. |

**Why not use the same bucket for both?**

1. **Circular dependency** — Terraform needs the state bucket to exist before it runs. If Terraform also manages that same bucket, `terraform destroy` would try to delete the bucket containing its own state file mid-operation.

2. **Accidental deletion** — `terraform destroy` on the workload would wipe the state file too. Separate buckets with `prevent_destroy = true` on the state bucket prevent this.

3. **Access control** — The state bucket should only be accessible to Terraform runners. Application buckets often need broader access. Mixing them makes IAM policies messy.

4. **Clarity** — At a glance: `*-state-*` = Terraform internals; everything else = real workloads.

In production you would reuse the **one state bucket** across many projects, each with a different `key` path:
```
s3://tf-remote-backend-state-.../
  ├── env:/<id>/infra/terraform.tfstate              ← this project
  ├── env:/<id>/another-project/terraform.tfstate
  └── env:/<id>/yet-another/terraform.tfstate
```

---

## Destroying Resources

### Destroy the infra workload

In env0, open the **dev environment** → click **Destroy** → approve. This removes the demo S3 bucket cleanly via Terraform.

### Destroy the bootstrap resources

> ⚠️ **Warning:** Destroying the state bucket deletes all Terraform state files. Destroy all other environments first.

1. In env0, destroy the **dev** environment first
2. In the AWS Console, empty the state bucket (you must delete all versions due to versioning being enabled)
3. Delete the state bucket
4. Delete the DynamoDB table
5. In env0, delete the bootstrap environment

---

## Troubleshooting

### `InvalidClientTokenId` — credentials rejected by AWS

Your AWS credentials are wrong or stale. In env0, open the environment → **Variables** tab and re-enter the `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` values marked as Sensitive. Confirm the key is **Active** in the AWS Console under IAM → Users → Security credentials.

---

### `BucketAlreadyOwnedByYou` during bootstrap

The S3 bucket already exists from a previous run — bootstrap has already succeeded. Skip to Phase 4 and configure the infra backend with the existing bucket name.

---

### `Error: required field is not set` during terraform init

The `infra/backend.tf` still contains placeholder values. Update the `bucket` and `dynamodb_table` fields with the real values from the bootstrap outputs and push the change.

---

### `Instance cannot be destroyed` — prevent_destroy error

The `prevent_destroy = true` lifecycle block is protecting the S3 bucket. This is intentional. To destroy it, comment out the lifecycle block in `bootstrap/main.tf` first.

---

### State lock not released after a failed deploy

In env0, open the environment → **Settings** → look for **Force Unlock**. Or via CLI:

```bash
cd infra/
terraform force-unlock <LOCK_ID>
```

---

## Variable Reference

### Bootstrap (`bootstrap/variables.tf`)

| Variable | Type | Default | Description |
|---|---|---|---|
| `aws_region` | string | `eu-central-1` | AWS region for backend resources |
| `project_name` | string | `tf-remote-backend` | Prefix for bucket and table names |
| `state_key_prefix` | string | `""` | Optional prefix inside the S3 bucket |

Bucket name derived as: `${project_name}-state-${account_id}-${region}`
Table name derived as: `${project_name}-locks`

### Infra (`infra/variables.tf`)

| Variable | Type | Default | Description |
|---|---|---|---|
| `aws_region` | string | `eu-central-1` | AWS region for workload resources |
| `project_name` | string | `tf-remote-backend-demo` | Used for naming the demo bucket |
| `environment` | string | `dev` | One of: `dev`, `staging`, `prod` |

Demo bucket name derived as: `${project_name}-${environment}-${account_id}`
