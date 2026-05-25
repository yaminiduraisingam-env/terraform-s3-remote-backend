<h3 align="left">
  <img width="600" height="128" alt="image" src="https://raw.githubusercontent.com/artemis-env0/Packages/refs/heads/main/Images/Logo%20Pack/01%20Main%20Logo/Digital/SVG/envzero_logomark_fullcolor_rgb.svg" />
</h3>

---

# OpenTofu S3 Remote Backend with DynamoDB State Locking (env0)

A complete, production-ready OpenTofu project that provisions an **AWS S3 remote backend** with **DynamoDB state locking**, deployed entirely through **env0** — no local OpenTofu commands required. All resources live in `eu-central-1` (Frankfurt).

---

## Table of Contents

1. [What This Project Does](#what-this-project-does)
2. [Why This Matters](#why-this-matters)
3. [Architecture Overview](#architecture-overview)
4. [Repository Structure](#repository-structure)
5. [Cost Breakdown](#cost-breakdown)
6. [Prerequisites](#prerequisites)
7. [End-to-End Deployment via env0](#end-to-end-deployment-via-env0)
   - [Phase 1 — AWS Setup](#phase-1--aws-setup)
   - [Phase 2 — Store AWS Credentials in env0](#phase-2--store-aws-credentials-in-env0)
   - [Phase 3 — Create the Bootstrap Template](#phase-3--create-the-bootstrap-template)
   - [Phase 4 — Deploy Bootstrap via env0](#phase-4--deploy-bootstrap-via-env0)
   - [Phase 5 — Configure the Infra Backend](#phase-5--configure-the-infra-backend)
   - [Phase 6 — Create the Infra Template](#phase-6--create-the-infra-template)
   - [Phase 7 — Deploy Infra via env0](#phase-7--deploy-infra-via-env0)
8. [Verifying the Remote Backend](#verifying-the-remote-backend)
9. [Viewing the State Lock Live](#viewing-the-state-lock-live)
10. [How State Locking Works](#how-state-locking-works)
11. [Why Two S3 Buckets?](#why-two-s3-buckets)
12. [Why OpenTofu over Terraform?](#why-opentofu-over-terraform)
13. [IAM Permissions](#iam-permissions)
14. [Teardown](#teardown)
15. [Troubleshooting](#troubleshooting)
16. [Variable Reference](#variable-reference)

---

## What This Project Does

This project provisions three AWS resources entirely through env0:

| Resource | Name | Purpose |
|---|---|---|
| S3 Bucket (state) | `tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1` | Stores OpenTofu state files remotely |
| DynamoDB Table (lock) | `tf-remote-backend-locks` | Prevents concurrent deployments from corrupting state |
| S3 Bucket (workload) | `tf-remote-backend-demo-dev-<ACCOUNT_ID>` | The proof resource — demonstrates a successful env0 deployment |

It is split into two layers:

- **Bootstrap** — runs once to create the state bucket and lock table
- **Infra** — runs on every deployment; creates workload resources with state stored in the bootstrap bucket

---

## Why This Matters

Without remote state, Terraform/OpenTofu state lives on a developer's laptop. This creates real problems:

| Problem | Impact |
|---|---|
| Two engineers deploy simultaneously | State files conflict and infrastructure gets corrupted |
| Developer leaves the company | State is on their laptop — nobody can manage infrastructure |
| Laptop gets wiped | State is gone — OpenTofu has no memory of what exists in AWS |
| No audit trail | No record of who changed what and when |

This project solves all of the above. Combined with env0's plan/approve workflow, every infrastructure change is reviewed, approved, logged, and auditable — which is exactly what financial services firms need to satisfy change management requirements.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                           env0 Platform                              │
│                                                                      │
│  ┌─────────────────────────┐    ┌─────────────────────────────────┐  │
│  │  Bootstrap Environment  │    │      Infra Environment (dev)    │  │
│  │                         │    │                                 │  │
│  │  Runs ONCE              │    │  Runs on every push to main     │  │
│  │  Creates state bucket   │    │  State stored in state bucket   │  │
│  │  Creates lock table     │    │  Lock acquired via DynamoDB     │  │
│  └────────────┬────────────┘    └──────────────┬──────────────────┘  │
└───────────────┼─────────────────────────────────┼────────────────────┘
                │ tofu apply                       │ tofu init + apply
                ▼                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                        AWS  eu-central-1                             │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  S3 State Bucket                                               │  │
│  │  tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1             │  │
│  │                                                                │  │
│  │  Versioned + AES-256 Encrypted + Private                       │  │
│  │  env:/<workspace>/infra/terraform.tfstate  ◄── written by      │  │
│  │                                                 env0 deploy    │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  DynamoDB Lock Table                                           │  │
│  │  tf-remote-backend-locks                                       │  │
│  │                                                                │  │
│  │  PAY_PER_REQUEST billing (~$0.00 at this usage level)          │  │
│  │  LockID written at start of plan/apply                         │  │
│  │  LockID deleted on completion                                  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  Demo Workload Bucket                                          │  │
│  │  tf-remote-backend-demo-dev-<ACCOUNT_ID>                       │  │
│  │                                                                │  │
│  │  Created by env0 infra deployment                              │  │
│  │  Proves the full pipeline works end to end                     │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
terraform-s3-remote-backend/
│
├── bootstrap/                   # Run ONCE via env0 — creates the backend infrastructure
│   ├── providers.tf             # OpenTofu + AWS provider version constraints
│   ├── variables.tf             # Input variables
│   ├── main.tf                  # S3 bucket + DynamoDB table resources
│   └── outputs.tf               # Outputs: state_bucket_name, dynamodb_table_name
│
├── infra/                       # Deployed via env0 on every push to main
│   ├── providers.tf             # OpenTofu + AWS provider version constraints
│   ├── backend.tf               # S3 remote backend config (updated after bootstrap)
│   ├── backend.hcl              # Partial backend config reference (documentation only)
│   ├── variables.tf             # Input variables
│   ├── main.tf                  # Demo S3 workload bucket
│   └── outputs.tf               # Outputs: app_bucket_name
│
├── iam-policy.json              # Minimum IAM permissions for the env0 IAM user
└── README.md                    # This file
```

---

## Cost Breakdown

| Service | Resource | Expected Monthly Cost |
|---|---|---|
| S3 | State bucket (< 1 MB of state files) | **$0.00** (Free Tier: 5 GB) |
| S3 | Demo workload bucket (empty) | **$0.00** |
| S3 | PUT/GET requests (< 100/month) | **$0.00** (Free Tier: 2,000 PUT) |
| DynamoDB | Lock table — PAY_PER_REQUEST | **< $0.01** (~2 ops per deploy) |
| DynamoDB | Storage (< 1 KB) | **$0.00** (Free Tier: 25 GB) |
| **Total** | | **< $0.01 / month** |

> Each DynamoDB lock operation costs ~$0.00000125. At 100 deploys/month the total is $0.00025 — effectively free.

---

## Prerequisites

### Tools

| Tool | Version | Install |
|---|---|---|
| AWS CLI | 2.x | https://aws.amazon.com/cli/ |
| Git | Any | https://git-scm.com |

> OpenTofu is installed and managed by env0 automatically — no local installation needed.

### Accounts

- **AWS account** with access to `eu-central-1`
- **IAM user** (e.g. `terraform-env0`) with `AdministratorAccess` attached
- **env0 account** — free at https://app.env0.com
- **GitHub repository** — this repo connected to your env0 organisation

---

## End-to-End Deployment via env0

Everything below is done through the **env0 UI** and **AWS Console**. The only terminal command in this entire guide is a single `git commit` in Phase 5.

---

### Phase 1 — AWS Setup

Before anything else, confirm your AWS credentials are working:

```bash
aws sts get-caller-identity
```

You should see your Account ID, User ARN, and User ID returned. Note your **Account ID** — you will need it in Phase 3.

> If you get `InvalidClientTokenId`, see [Troubleshooting](#troubleshooting).

---

### Phase 2 — Store AWS Credentials in env0

Store your credentials once here and both environments will use them.

1. In env0, click **Organisation Settings** (bottom-left) → **Credentials**
2. Click **+ Add Credentials** → select **AWS Access Keys**
3. Enter your IAM user's **Access Key ID** and **Secret Access Key**
4. Name it `aws-eu-central-1`
5. Click **Save**

> Never put AWS credentials in plain-text Terraform/OpenTofu Variables. The Credentials store encrypts them and ensures they never appear in deployment logs.

---

### Phase 3 — Create the Bootstrap Template

The bootstrap template points env0 at the `bootstrap/` folder and defines how to deploy it.

1. In env0, navigate to **Project → Templates → New Template**
2. Select **OpenTofu** as the IaC type
3. Set **OpenTofu Version** to `1.8.0`
4. Connect to **GitHub** and select this repository
5. Set **Branch** to `main`
6. Set **Terraform Folder** to `bootstrap`
7. On the **Variables** screen, add:

| Key | Value | Sensitive |
|---|---|---|
| `aws_region` | `eu-central-1` | Clear Text |
| `project_name` | `tf-remote-backend` | Clear Text |
| `state_bucket_name` | `tf-remote-backend-state-<YOUR_ACCOUNT_ID>-eu-central-1` | Clear Text |

8. Name the template `terraform-s3-remote-backend-bootstrap`
9. Assign it to your project and save

---

### Phase 4 — Deploy Bootstrap via env0

1. Open the bootstrap template → click **New Environment**
2. Set **Environment Name** to `bootstrap`
3. Set **Workspace Name** to `bootstrap`
4. Under **Environment Variables** add:

| Key | Value | Sensitive |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | your key ID | **Yes — Sensitive** |
| `AWS_SECRET_ACCESS_KEY` | your secret key | **Yes — Sensitive** |

5. Set **Destroy in X hours** to **Never**
6. Click **Run**

env0 runs `tofu init` → `tofu plan`. You should see the following in the plan:

```
+ aws_dynamodb_table.terraform_locks
+ aws_s3_bucket.terraform_state
+ aws_s3_bucket_lifecycle_configuration.terraform_state
+ aws_s3_bucket_public_access_block.terraform_state
+ aws_s3_bucket_server_side_encryption_configuration.terraform_state
+ aws_s3_bucket_versioning.terraform_state

Plan: 6 to add, 0 to change, 0 to destroy.
```

Click **Approve**.

After the apply completes, click the **Resources** tab in env0 and note the outputs:

- `state_bucket_name` → e.g. `tf-remote-backend-state-013141018419-eu-central-1`
- `dynamodb_table_name` → e.g. `tf-remote-backend-locks`

You need both values for the next phase.

---

### Phase 5 — Configure the Infra Backend

Now that the S3 bucket and DynamoDB table exist in AWS, update `infra/backend.tf` with the real values.

Open `infra/backend.tf` and replace the contents:

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

Replace `013141018419` with your actual AWS Account ID. Commit and push:

```bash
git add infra/backend.tf
git commit -m "chore: configure infra S3 backend with bootstrap outputs"
git push
```

> **Why hardcode the values?** env0 runs `tofu init` in an isolated runner without access to your local filesystem. Hardcoding directly in `backend.tf` is the most reliable approach for CI/CD platforms.

---

### Phase 6 — Create the Infra Template

1. In env0, navigate to **Project → Templates → New Template**
2. Select **OpenTofu** as the IaC type
3. Set **OpenTofu Version** to `1.8.0`
4. Connect to the same GitHub repository
5. Set **Branch** to `main`
6. Set **Terraform Folder** to `infra`
7. On the **Variables** screen, add:

| Key | Value | Sensitive |
|---|---|---|
| `aws_region` | `eu-central-1` | Clear Text |
| `environment` | `dev` | Clear Text |
| `project_name` | `tf-remote-backend-demo` | Clear Text |

8. Name the template `terraform-s3-remote-backend-infra`
9. Assign it to your project and save

---

### Phase 7 — Deploy Infra via env0

1. Open the infra template → click **New Environment**
2. Set **Environment Name** to `dev`
3. Set **Workspace Name** to `dev`
4. Under **Environment Variables** add the same AWS credentials as Phase 4
5. Set **Destroy in X hours** to **Never**
6. Click **Run**

env0 initialises against the S3 backend, then plans. You should see:

```
+ aws_s3_bucket.app
+ aws_s3_bucket_public_access_block.app
+ aws_s3_bucket_server_side_encryption_configuration.app
+ aws_s3_bucket_versioning.app

Plan: 4 to add, 0 to change, 0 to destroy.
```

Click **Approve**.

After the apply completes you will have all three resources running in AWS:

| Resource | Name |
|---|---|
| S3 state bucket | `tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1` |
| DynamoDB lock table | `tf-remote-backend-locks` |
| S3 demo workload bucket | `tf-remote-backend-demo-dev-<ACCOUNT_ID>` |

---

## Verifying the Remote Backend

After the infra deploy, confirm the state file was written to S3.

**In the AWS Console:**
1. Go to **S3** → click `tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1`
2. You will see a folder prefixed with `env:/` — this is env0's workspace namespace
3. Navigate into it → `infra/` → `terraform.tfstate`

**Via CLI:**
```bash
aws s3 ls s3://tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1/ --recursive --region eu-central-1
```

Expected output:
```
2026-04-24 10:22:27   6702   env:/<workspace-id>/infra/terraform.tfstate
```

**In env0:**
- Open the **dev environment** → click the **Resources** tab to see every managed resource rendered visually from the state file

> env0 automatically namespaces state under `env:/<workspace-id>/` so multiple environments sharing the same bucket never collide.

---

## Viewing the State Lock Live

The DynamoDB lock only exists for a **few seconds during an active plan or apply**. To catch it:

1. Open **two browser tabs** side by side:
   - Tab 1: env0 infra environment
   - Tab 2: AWS Console → DynamoDB → `tf-remote-backend-locks` → **Explore table items**

2. In Tab 1 click **Redeploy**

3. Immediately switch to Tab 2 and click **Run** (Scan)

You will briefly see a row like:

```json
{
  "LockID": "tf-remote-backend-state-.../infra/terraform.tfstate",
  "Info": "{\"Operation\":\"OperationTypePlan\",\"Who\":\"env0-runner@...\"}"
}
```

After the deploy completes the table will be **empty** — this is correct. An empty table proves the lock was properly acquired and released.

> If a lock row persists after a failed deploy, OpenTofu will refuse all future operations until it is cleared. See [Troubleshooting](#troubleshooting).

---

## How State Locking Works

```
env0 triggers tofu plan / apply
        │
        ▼
1. ACQUIRE LOCK
   DynamoDB PutItem
   LockID: "tf-remote-backend-state-.../infra/terraform.tfstate"
        │
        ▼
2. FETCH CURRENT STATE
   S3 GetObject → env:/<workspace>/infra/terraform.tfstate
        │
        ▼
3. CALCULATE DIFF / APPLY CHANGES IN AWS
        │
        ▼
4. WRITE UPDATED STATE
   S3 PutObject → new version of terraform.tfstate written
        │
        ▼
5. RELEASE LOCK
   DynamoDB DeleteItem → lock row removed
```

If two deploys run simultaneously, the second one fails immediately:

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

| Bucket | Purpose |
|---|---|
| `tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1` | **The filing cabinet** — stores OpenTofu state. Infrastructure for OpenTofu itself. |
| `tf-remote-backend-demo-dev-<ACCOUNT_ID>` | **The workload** — the actual deployed resource. In a real project this holds application data. |

**Why not use the same bucket for both?**

1. **Circular dependency** — OpenTofu needs the state bucket to exist before it can run. If OpenTofu also manages that same bucket, running `tofu destroy` would attempt to delete the bucket that contains its own state file mid-operation.

2. **Accidental deletion** — `tofu destroy` on the workload would wipe the state file. The state bucket has `prevent_destroy = true` to prevent this.

3. **Access control** — The state bucket should only be accessible to OpenTofu runners. Application buckets often need broader access for other services or teams.

4. **Clarity** — `*-state-*` = OpenTofu internals. Everything else = real workloads.

In production the one state bucket is reused across every project, each with a different `key` path:

```
s3://tf-remote-backend-state-.../
  ├── env:/<id>/infra/terraform.tfstate
  ├── env:/<id>/another-project/terraform.tfstate
  └── env:/<id>/production/terraform.tfstate
```

---

## Why OpenTofu over Terraform?

In August 2023, HashiCorp changed Terraform's licence from open source (MPL 2.0) to the Business Source Licence (BSL). This means Terraform is no longer fully open source and introduces restrictions on commercial use that affect some organisations.

OpenTofu is the open source fork of Terraform, maintained by the Linux Foundation, that guarantees the tooling remains free and open source permanently.

| | Terraform | OpenTofu |
|---|---|---|
| Licence | BSL — commercial restrictions apply | MPL 2.0 — fully open source |
| Syntax | HCL | HCL (identical) |
| Provider registry | registry.terraform.io | Compatible with same registry |
| S3 backend support | ✅ | ✅ |
| env0 support | ✅ | ✅ Native |

For financial services firms where procurement and legal teams scrutinise software licences, OpenTofu removes a conversation that Terraform now requires.

---

## IAM Permissions

The `iam-policy.json` file contains the minimum IAM permissions required. Key actions:

| Permission | Why needed |
|---|---|
| `s3:GetObject` / `s3:PutObject` | Read and write the state file |
| `s3:ListBucket` | Check if the state file exists |
| `s3:GetBucketPolicy` | Required by the AWS provider when reading bucket state |
| `dynamodb:GetItem` / `PutItem` / `DeleteItem` | Acquire and release state locks |
| `dynamodb:DescribeTable` | Verify the lock table is active |
| `dynamodb:DescribeTimeToLive` | Required by the AWS provider when reading table state |
| `sts:GetCallerIdentity` | Used by `data.aws_caller_identity.current` |

> Start with `AdministratorAccess` for initial setup. Replace with `iam-policy.json` once everything is working.

---

## Teardown

**Always destroy in this order — infra first, bootstrap second.**

### Step 1 — Destroy the infra workload

In env0 → open the **dev environment** → click **Destroy** → Approve.

This removes the demo S3 bucket cleanly via OpenTofu.

### Step 2 — Destroy the bootstrap resources

In env0 → open the **bootstrap environment** → click **Destroy** → Approve.

This removes the state S3 bucket and DynamoDB table.

> The state S3 bucket has versioning enabled. If the destroy fails with `BucketNotEmpty`, the bucket must be emptied first. See [Troubleshooting](#troubleshooting).

### Step 3 — Verify AWS is clean

```bash
aws s3 ls | grep tf-remote-backend
aws dynamodb list-tables --region eu-central-1
```

Both should return nothing.

---

## Troubleshooting

### `InvalidClientTokenId` — AWS credentials rejected

Your credentials are wrong, stale, or environment variables are overriding your config file. Run:

```bash
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
aws sts get-caller-identity
```

If the key was just created in the AWS Console, wait 60 seconds for IAM propagation and retry. Confirm the key is **Active** under IAM → Users → Security credentials.

---

### `BucketAlreadyOwnedByYou` during bootstrap

The state bucket already exists from a previous run — bootstrap has already succeeded. Skip directly to Phase 5.

---

### `Error: required field is not set` during tofu init

The `infra/backend.tf` still contains placeholder values. Update `bucket` and `dynamodb_table` with the real values from the bootstrap outputs and push the change.

---

### `BucketNotEmpty` when destroying bootstrap

The S3 bucket has versioned objects that must be deleted before the bucket itself can be deleted. Run the following three commands:

```bash
# Delete all object versions
aws s3api delete-objects \
  --bucket tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1 \
  --delete "$(aws s3api list-object-versions \
    --bucket tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1 \
    --region eu-central-1 \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json)" \
  --region eu-central-1

# Delete all delete markers
aws s3api delete-objects \
  --bucket tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1 \
  --delete "$(aws s3api list-object-versions \
    --bucket tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1 \
    --region eu-central-1 \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
    --output json)" \
  --region eu-central-1

# Delete the now-empty bucket
aws s3api delete-bucket \
  --bucket tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1 \
  --region eu-central-1
```

Then click **Delete Environment** in env0 on the bootstrap environment.

---

### State lock not released after a failed deploy

In env0 → environment → **Settings** → look for **Force Unlock**. Or via CLI:

```bash
cd infra/
tofu force-unlock <LOCK_ID>
```

---

### Accidentally deleted bootstrap before infra

The infra environment cannot run `tofu destroy` because its S3 backend no longer exists. In the AWS Console, check whether the demo workload bucket still exists and delete it manually:

```bash
aws s3 rb s3://tf-remote-backend-demo-dev-<ACCOUNT_ID> --force --region eu-central-1
```

Then in env0 click **Delete Environment** (not Destroy) on the infra environment.

---

## Variable Reference

### Bootstrap (`bootstrap/variables.tf`)

| Variable | Type | Default | Description |
|---|---|---|---|
| `aws_region` | string | `eu-central-1` | AWS region for backend resources |
| `project_name` | string | `tf-remote-backend` | Prefix for bucket and table names |
| `state_bucket_name` | string | — | Full S3 bucket name — set in env0 variables |

Bucket name pattern: `${project_name}-state-${account_id}-${region}`
Table name pattern: `${project_name}-locks`

### Infra (`infra/variables.tf`)

| Variable | Type | Default | Description |
|---|---|---|---|
| `aws_region` | string | `eu-central-1` | AWS region for workload resources |
| `project_name` | string | `tf-remote-backend-demo` | Prefix for the workload bucket name |
| `environment` | string | `dev` | Deployment environment: `dev`, `staging`, or `prod` |

Workload bucket name pattern: `${project_name}-${environment}-${account_id}`
