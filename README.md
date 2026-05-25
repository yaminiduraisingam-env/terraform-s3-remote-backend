<h3 align="left">
  <img width="600" height="128" alt="image" src="https://raw.githubusercontent.com/artemis-env0/Packages/refs/heads/main/Images/Logo%20Pack/01%20Main%20Logo/Digital/SVG/envzero_logomark_fullcolor_rgb.svg" />
</h3>

---

# OpenTofu + Terragrunt S3 Remote Backend with DynamoDB State Locking (env0)

A complete, production-ready project that provisions an **AWS S3 remote backend** with **DynamoDB state locking** using **OpenTofu** and **Terragrunt**, deployed entirely through **env0**. All resources live in `eu-central-1` (Frankfurt).

---

## Table of Contents

1. [What This Project Does](#what-this-project-does)
2. [Why This Stack](#why-this-stack)
3. [How Terragrunt Works Here](#how-terragrunt-works-here)
4. [Architecture Overview](#architecture-overview)
5. [Repository Structure](#repository-structure)
6. [Cost Breakdown](#cost-breakdown)
7. [Prerequisites](#prerequisites)
8. [End-to-End Deployment via env0](#end-to-end-deployment-via-env0)
   - [Phase 1 — AWS Setup](#phase-1--aws-setup)
   - [Phase 2 — Store AWS Credentials in env0](#phase-2--store-aws-credentials-in-env0)
   - [Phase 3 — Create the Bootstrap Template](#phase-3--create-the-bootstrap-template)
   - [Phase 4 — Deploy Bootstrap via env0](#phase-4--deploy-bootstrap-via-env0)
   - [Phase 5 — Create the App-Bucket Template](#phase-5--create-the-app-bucket-template)
   - [Phase 6 — Deploy App-Bucket via env0](#phase-6--deploy-app-bucket-via-env0)
9. [Verifying the Remote Backend](#verifying-the-remote-backend)
10. [Viewing the State Lock Live](#viewing-the-state-lock-live)
11. [How State Locking Works](#how-state-locking-works)
12. [Why Two S3 Buckets?](#why-two-s3-buckets)
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
| DynamoDB Table (lock) | `tf-remote-backend-locks` | Prevents concurrent deployments corrupting state |
| S3 Bucket (workload) | `tf-remote-backend-demo-dev-<ACCOUNT_ID>` | Proof resource — shows a successful env0 deployment |

It is split into two layers:

- **Bootstrap** — runs once to create the state bucket and lock table
- **App-bucket** — runs on every deployment; creates the workload bucket with state stored in the bootstrap bucket

---

## Why This Stack

### OpenTofu over Terraform

In August 2023, HashiCorp changed Terraform's licence from open source (MPL 2.0) to the Business Source Licence (BSL), introducing commercial restrictions. OpenTofu is the Linux Foundation-backed open source fork that guarantees the tooling remains free and unrestricted permanently. The current stable release is **v1.11.6** (April 2026).

| | Terraform | OpenTofu |
|---|---|---|
| Licence | BSL — commercial restrictions | MPL 2.0 — fully open source |
| Syntax | HCL | HCL (identical) |
| S3 backend + DynamoDB locking | ✅ | ✅ |
| env0 support | ✅ | ✅ Native |

For financial services firms where procurement teams scrutinise software licences, OpenTofu removes a conversation Terraform now requires.

### Terragrunt over plain OpenTofu

Without Terragrunt, every environment requires a manually maintained `backend.tf` with hardcoded bucket names, table names, and regions. This doesn't scale.

Terragrunt defines the backend **once** in the root `terragrunt.hcl` and generates `backend.tf` automatically for every environment at runtime. Adding a new environment is a single `terragrunt.hcl` file — no copy-paste, no manual backend configuration.

This project uses **Terragrunt 1.0** — the first stable release (March 2026) with a formal backwards compatibility commitment. For a financial services team that needs confidence their tooling won't break between upgrades, the 1.0 stability guarantee matters.

---

## How Terragrunt Works Here

The root `terragrunt.hcl` defines the S3 backend configuration once:

```hcl
remote_state {
  backend = "s3"
  config = {
    bucket         = "tf-remote-backend-state-${get_aws_account_id()}-eu-central-1"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "tf-remote-backend-locks"
  }
}
```

Any environment that includes the root config with `include "root" { path = find_in_parent_folders() }` automatically gets a generated `backend.tf` with the correct values. The `key` is set dynamically using the environment's path relative to the root — so each environment gets a unique state file location without any manual configuration.

The bootstrap environment is the **one exception** — it intentionally does not inherit the root config because it is responsible for creating the bucket. env0 manages its state internally.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                           env0 Platform                              │
│                                                                      │
│  ┌─────────────────────────┐    ┌─────────────────────────────────┐  │
│  │  Bootstrap Environment  │    │    App-Bucket Environment       │  │
│  │                         │    │                                 │  │
│  │  Runs ONCE              │    │  Runs on every push to main     │  │
│  │  State: env0 managed    │    │  State: S3 remote backend       │  │
│  │  No remote backend      │    │  Lock: DynamoDB                 │  │
│  └────────────┬────────────┘    └──────────────┬──────────────────┘  │
└───────────────┼─────────────────────────────────┼────────────────────┘
                │ tofu apply (via terragrunt)      │ tofu init + apply
                ▼                                  ▼ (via terragrunt)
┌──────────────────────────────────────────────────────────────────────┐
│                        AWS  eu-central-1                             │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  S3 State Bucket                                               │  │
│  │  tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1             │  │
│  │                                                                │  │
│  │  Versioned + AES-256 Encrypted + Fully Private                 │  │
│  │  live/dev/app-bucket/terraform.tfstate  ◄── written by env0    │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  DynamoDB Lock Table                                           │  │
│  │  tf-remote-backend-locks                                       │  │
│  │                                                                │  │
│  │  PAY_PER_REQUEST — effectively free at this usage level        │  │
│  │  LockID written at start of every plan/apply                   │  │
│  │  LockID deleted on completion                                  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  Demo Workload Bucket                                          │  │
│  │  tf-remote-backend-demo-dev-<ACCOUNT_ID>                       │  │
│  │                                                                │  │
│  │  Created by env0 app-bucket deployment                         │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
opentofu-s3-remote-backend/
│
├── terragrunt.hcl               # ROOT — defines S3 backend and AWS provider ONCE
│                                #        all environments under live/ inherit this
│
├── modules/                     # Reusable OpenTofu modules (no backend config)
│   ├── bootstrap/               # Module: creates S3 state bucket + DynamoDB table
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── app-bucket/              # Module: creates demo workload S3 bucket
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── live/                        # Environment-specific Terragrunt configs
│   ├── bootstrap/
│   │   └── terragrunt.hcl       # Calls modules/bootstrap — NO root include
│   └── dev/
│       └── app-bucket/
│           └── terragrunt.hcl   # Calls modules/app-bucket — inherits root
│
├── .gitignore
└── README.md
```

> **Key point:** There are no `backend.tf` or `provider.tf` files in this repo. Terragrunt generates them at runtime from the root `terragrunt.hcl`. This is intentional — they are listed in `.gitignore`.

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

---

## Prerequisites

### Tools

| Tool | Version | Install |
|---|---|---|
| AWS CLI | 2.x | https://aws.amazon.com/cli/ |
| Git | Any | https://git-scm.com |

> OpenTofu and Terragrunt are installed and managed by env0 automatically — no local installation needed.

### Accounts

- **AWS account** with access to `eu-central-1`
- **IAM user** (e.g. `opentofu-env0`) with `AdministratorAccess` attached
- **env0 account** — free at https://app.env0.com
- **GitHub repository** — this repo connected to your env0 organisation

---

## End-to-End Deployment via env0

Everything below is done through the **env0 UI** and **AWS Console**. No local OpenTofu or Terragrunt commands are needed.

---

### Phase 1 — AWS Setup

Confirm your AWS credentials are working:

```bash
aws sts get-caller-identity
```

You should see your Account ID, User ARN, and User ID. Note your **Account ID** — you will need it in Phase 3.

---

### Phase 2 — Store AWS Credentials in env0

1. In env0, click **Organisation Settings** (bottom-left) → **Credentials**
2. Click **+ Add Credentials** → select **AWS Access Keys**
3. Enter your IAM user's Access Key ID and Secret Access Key
4. Name it `aws-eu-central-1`
5. Click **Save**

> Never put AWS credentials in plain-text variables. The Credentials store encrypts them so they never appear in logs.

---

### Phase 3 — Create the Bootstrap Template

1. In env0, navigate to **Project → Templates → New Template**
2. Set **IaC Type** to **Terragrunt**
3. Set **OpenTofu Version** to `1.11.6`
4. Set **Terragrunt Version** to `1.0.5`
5. Connect to **GitHub** and select this repository
6. Set **Branch** to `main`
7. Set **Terraform Folder** to `live/bootstrap`
8. On the **Variables** screen, add:

| Key | Value | Sensitive |
|---|---|---|
| `aws_region` | `eu-central-1` | Clear Text |
| `project_name` | `tf-remote-backend` | Clear Text |

9. Name the template `opentofu-s3-remote-backend-bootstrap`
10. Assign to your project and save

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

env0 runs `terragrunt init` → `terragrunt plan`. You should see:

```
+ aws_dynamodb_table.lock
+ aws_s3_bucket.state
+ aws_s3_bucket_lifecycle_configuration.state
+ aws_s3_bucket_public_access_block.state
+ aws_s3_bucket_server_side_encryption_configuration.state
+ aws_s3_bucket_versioning.state

Plan: 6 to add, 0 to change, 0 to destroy.
```

Click **Approve**.

After the apply completes, click the **Resources** tab and note:

- `state_bucket_name` → e.g. `tf-remote-backend-state-013141018419-eu-central-1`
- `dynamodb_table_name` → e.g. `tf-remote-backend-locks`

---

### Phase 5 — Create the App-Bucket Template

1. In env0, navigate to **Project → Templates → New Template**
2. Set **IaC Type** to **Terragrunt**
3. Set **OpenTofu Version** to `1.11.6`
4. Set **Terragrunt Version** to `1.0.5`
5. Connect to the same GitHub repository
6. Set **Branch** to `main`
7. Set **Terraform Folder** to `live/dev/app-bucket`
8. On the **Variables** screen, add:

| Key | Value | Sensitive |
|---|---|---|
| `aws_region` | `eu-central-1` | Clear Text |
| `environment` | `dev` | Clear Text |
| `project_name` | `tf-remote-backend-demo` | Clear Text |

9. Name the template `opentofu-s3-remote-backend-app-bucket`
10. Assign to your project and save

---

### Phase 6 — Deploy App-Bucket via env0

1. Open the app-bucket template → click **New Environment**
2. Set **Environment Name** to `dev`
3. Set **Workspace Name** to `dev`
4. Add the same AWS credentials as Phase 4
5. Set **Destroy in X hours** to **Never**
6. Click **Run**

Terragrunt reads the root `terragrunt.hcl`, generates `backend.tf` automatically pointing at the state bucket, then runs `tofu init` and `tofu plan`. You should see:

```
+ aws_s3_bucket.app
+ aws_s3_bucket_public_access_block.app
+ aws_s3_bucket_server_side_encryption_configuration.app
+ aws_s3_bucket_versioning.app

Plan: 4 to add, 0 to change, 0 to destroy.
```

Click **Approve**.

After the apply completes you will have all three AWS resources:

| Resource | Name |
|---|---|
| S3 state bucket | `tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1` |
| DynamoDB lock table | `tf-remote-backend-locks` |
| S3 demo workload bucket | `tf-remote-backend-demo-dev-<ACCOUNT_ID>` |

---

## Verifying the Remote Backend

After the app-bucket deploy, confirm the state file was written to S3.

**In the AWS Console:**
1. Go to **S3** → click `tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1`
2. You will see a folder prefixed with `env:/` — env0's workspace namespace
3. Navigate into it → `live/dev/app-bucket/` → `terraform.tfstate`

**Via CLI:**
```bash
aws s3 ls s3://tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1/ \
  --recursive --region eu-central-1
```

Expected output:
```
2026-05-25 10:22:27   6702   env:/<workspace-id>/live/dev/app-bucket/terraform.tfstate
```

**In env0:**
Open the **dev environment** → **Resources** tab to see every managed resource rendered visually from the state file.

> env0 automatically namespaces state under `env:/<workspace-id>/` so multiple environments sharing the same bucket never collide.

---

## Viewing the State Lock Live

The DynamoDB lock only exists for a **few seconds during an active plan or apply**. To catch it:

1. Open **two browser tabs** side by side:
   - Tab 1: env0 app-bucket environment
   - Tab 2: AWS Console → DynamoDB → `tf-remote-backend-locks` → **Explore table items**
2. In Tab 1 click **Redeploy**
3. Immediately switch to Tab 2 and click **Run** (Scan)

You will briefly see:

```json
{
  "LockID": "tf-remote-backend-state-.../live/dev/app-bucket/terraform.tfstate",
  "Info": "{\"Operation\":\"OperationTypePlan\",\"Who\":\"env0-runner@...\"}"
}
```

After the deploy completes the table will be **empty** — the lock was properly acquired and released.

---

## How State Locking Works

```
env0 triggers terragrunt plan / apply
        │
        ▼
Terragrunt generates backend.tf from root terragrunt.hcl
        │
        ▼
1. ACQUIRE LOCK
   DynamoDB PutItem
   LockID: "tf-remote-backend-state-.../live/dev/app-bucket/terraform.tfstate"
        │
        ▼
2. FETCH CURRENT STATE
   S3 GetObject → env:/<workspace>/live/dev/app-bucket/terraform.tfstate
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

If two deploys run simultaneously the second one fails immediately — protecting the state file from corruption.

---

## Why Two S3 Buckets?

| Bucket | Purpose |
|---|---|
| `tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1` | **The filing cabinet** — stores OpenTofu state. Infrastructure for OpenTofu itself. |
| `tf-remote-backend-demo-dev-<ACCOUNT_ID>` | **The workload** — the actual deployed resource. In a real project this holds application data. |

They must be separate because OpenTofu needs the state bucket to exist **before** it runs. If OpenTofu also managed that bucket as a resource, `tofu destroy` would attempt to delete the bucket containing its own state file mid-operation.

In production the one state bucket is reused across every project, each with a different `key` path:

```
s3://tf-remote-backend-state-.../
  ├── env:/<id>/live/dev/app-bucket/terraform.tfstate
  ├── env:/<id>/live/dev/another-service/terraform.tfstate
  └── env:/<id>/live/prod/app-bucket/terraform.tfstate
```

---

## IAM Permissions

The `iam-policy.json` file contains the minimum permissions required:

| Permission | Why needed |
|---|---|
| `s3:GetObject` / `s3:PutObject` | Read and write the state file |
| `s3:ListBucket` | Check if the state file exists |
| `s3:GetBucketPolicy` | Required by the AWS provider when reading bucket state |
| `dynamodb:GetItem` / `PutItem` / `DeleteItem` | Acquire and release state locks |
| `dynamodb:DescribeTable` | Verify the lock table is active |
| `dynamodb:DescribeTimeToLive` | Required by the AWS provider |
| `sts:GetCallerIdentity` | Used by `data.aws_caller_identity.current` |

> Start with `AdministratorAccess` for initial setup. Replace with the minimal policy once everything is working.

---

## Teardown

**Always destroy in this order — app-bucket first, bootstrap second.**

### Step 1 — Destroy the app-bucket workload

In env0 → open the **dev environment** → click **Destroy** → Approve.

### Step 2 — Destroy the bootstrap resources

In env0 → open the **bootstrap environment** → click **Destroy** → Approve.

The state bucket has `force_destroy = true` set — env0 will empty all versioned objects automatically before deletion. No manual steps needed.

### Step 3 — Verify AWS is clean

```bash
aws s3 ls | grep tf-remote-backend
aws dynamodb list-tables --region eu-central-1
```

Both should return nothing.

---

## Troubleshooting

### `InvalidClientTokenId` — AWS credentials rejected

```bash
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
aws sts get-caller-identity
```

Confirm the key is Active in AWS Console → IAM → Users → Security credentials. If just created, wait 60 seconds for IAM propagation.

---

### Bootstrap plan shows 0 resources

Terragrunt may be pointing at an empty directory. Confirm the env0 template's **Terraform Folder** is set to `live/bootstrap` — not `bootstrap/` or `modules/bootstrap`.

---

### App-bucket init fails with `bucket does not exist`

Bootstrap has not been deployed yet, or was deployed to a different account. Deploy bootstrap first and confirm the state bucket exists in AWS Console → S3.

---

### State lock not released after a failed deploy

In env0 → environment → **Settings** → **Force Unlock**. Or via CLI:

```bash
tofu force-unlock <LOCK_ID>
```

---

### Accidentally deleted bootstrap before app-bucket

The app-bucket environment cannot init because its S3 backend no longer exists. Delete the workload bucket manually if it still exists, then click **Delete Environment** in env0 on the app-bucket environment.

```bash
aws s3 rb s3://tf-remote-backend-demo-dev-<ACCOUNT_ID> --force --region eu-central-1
```

---

## Variable Reference

### Bootstrap module (`modules/bootstrap/variables.tf`)

| Variable | Type | Default | Description |
|---|---|---|---|
| `aws_region` | string | `eu-central-1` | AWS region for backend resources |
| `project_name` | string | `tf-remote-backend` | Prefix for bucket and table names |

Resources created:
- Bucket: `${project_name}-state-${account_id}-${region}`
- Table: `${project_name}-locks`

### App-bucket module (`modules/app-bucket/variables.tf`)

| Variable | Type | Default | Description |
|---|---|---|---|
| `aws_region` | string | `eu-central-1` | AWS region for the workload bucket |
| `project_name` | string | `tf-remote-backend-demo` | Prefix for the bucket name |
| `environment` | string | `dev` | One of: `dev`, `staging`, `prod` |

Workload bucket name: `${project_name}-${environment}-${account_id}`
