# Terraform S3 Remote Backend + env0

A fully working example of a **Terraform remote backend** using **Amazon S3** for state storage and **DynamoDB** for state locking, deployed to `eu-central-1` and driven by **env0**.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Repository Structure](#repository-structure)
3. [How It Works](#how-it-works)
4. [Cost Analysis](#cost-analysis)
5. [Prerequisites](#prerequisites)
6. [Step-by-Step Setup Guide](#step-by-step-setup-guide)
   - [Phase 1 — AWS Credentials](#phase-1--aws-credentials)
   - [Phase 2 — Run the Bootstrap Workspace](#phase-2--run-the-bootstrap-workspace)
   - [Phase 3 — Configure the Infra Backend](#phase-3--configure-the-infra-backend)
   - [Phase 4 — Connect to env0](#phase-4--connect-to-env0)
   - [Phase 5 — Deploy via env0](#phase-5--deploy-via-env0)
7. [IAM Permissions](#iam-permissions)
8. [env0 Configuration Deep Dive](#env0-configuration-deep-dive)
9. [Verifying the Remote Backend](#verifying-the-remote-backend)
10. [Teardown](#teardown)
11. [Troubleshooting](#troubleshooting)
12. [Key Terraform Concepts Used](#key-terraform-concepts-used)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          eu-central-1                               │
│                                                                     │
│   ┌──────────────────────────────────────────────────────────────┐  │
│   │  BOOTSTRAP WORKSPACE (run once)                              │  │
│   │                                                              │  │
│   │  ┌─────────────────────────────┐  ┌───────────────────────┐ │  │
│   │  │  S3 Bucket                  │  │  DynamoDB Table        │ │  │
│   │  │  tf-remote-backend-state-   │  │  tf-remote-backend-   │ │  │
│   │  │  <ACCOUNT_ID>-eu-central-1  │  │  locks                │ │  │
│   │  │                             │  │                        │ │  │
│   │  │  • Versioning: ON           │  │  • billing: PAY_PER_  │ │  │
│   │  │  • Encryption: AES-256      │  │    REQUEST            │ │  │
│   │  │  • Public access: BLOCKED   │  │  • hash_key: LockID   │ │  │
│   │  │  • Lifecycle: 90-day expiry │  │                        │ │  │
│   │  └─────────────────────────────┘  └───────────────────────┘ │  │
│   └──────────────────────────────────────────────────────────────┘  │
│                                │                    │                │
│                    stores state files        acquires lock           │
│                                │                    │                │
│   ┌────────────────────────────▼────────────────────▼────────────┐  │
│   │  INFRA WORKSPACE (regular deploys)                           │  │
│   │                                                              │  │
│   │  ┌────────────────────────────────────────────────────────┐  │  │
│   │  │  S3 Bucket  (the "proof" resource)                     │  │  │
│   │  │  my-project-dev-<ACCOUNT_ID>                           │  │  │
│   │  └────────────────────────────────────────────────────────┘  │  │
│   └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

              ▲                        ▲
              │  triggered by          │  triggered by
         ┌────┴──────┐           ┌─────┴──────┐
         │  env0     │           │  env0      │
         │ bootstrap │           │   infra    │
         │ environment│          │ environment│
         └───────────┘           └────────────┘
```

---

## Repository Structure

```
terraform-s3-remote-backend/
│
├── bootstrap/                  # Phase 1: creates the backend resources
│   ├── providers.tf            # AWS provider + Terraform version constraints
│   ├── variables.tf            # aws_region, project_name, state_key_prefix
│   ├── main.tf                 # S3 bucket, DynamoDB table + supporting resources
│   └── outputs.tf              # Bucket/table names + a ready-to-paste backend.hcl snippet
│
├── infra/                      # Phase 2: real workload using the remote backend
│   ├── backend.tf              # Empty S3 backend block (partial config pattern)
│   ├── backend.hcl             # Backend values — fill in ACCOUNT_ID then commit
│   ├── providers.tf            # AWS provider + Terraform version constraints
│   ├── variables.tf            # aws_region, project_name, environment
│   ├── main.tf                 # Application S3 bucket (the "proof" resource)
│   └── outputs.tf              # Bucket name, ARN, remote state location
│
├── env0.yml                    # env0 Environments-as-Code (EaC) definition
├── iam-policy.json             # Minimal IAM policy for the Terraform executor
├── .gitignore
└── README.md
```

---

## How It Works

### The chicken-and-egg problem

Terraform's S3 backend requires an S3 bucket and a DynamoDB table to already exist before `terraform init` can succeed. Those resources cannot be created *by the workspace that uses them* as the backend.

This project solves the problem with two workspaces:

| Workspace | Backend | Purpose |
|-----------|---------|---------|
| `bootstrap` | **local** (managed by env0) | Creates the S3 bucket + DynamoDB table |
| `infra` | **S3 remote** (the bucket above) | Creates your real infrastructure |

### State locking explained

When any `terraform apply` or `terraform plan` starts, the S3 backend:

1. Writes a lock record to DynamoDB (`PutItem` on the `LockID` hash key).
2. Runs the Terraform operation.
3. Deletes the lock record (`DeleteItem`) when done.

If a second process tries to run while the lock exists, it reads the existing item and fails with a clear error showing who holds the lock. This prevents two concurrent applies from corrupting the state file.

---

## Cost Analysis

All resources in this project are either free or negligible in cost.

| Resource | Pricing model | Expected monthly cost |
|----------|---------------|-----------------------|
| S3 bucket (state files) | $0.023/GB — state files are KB-sized | **~$0.00** |
| S3 versioning (old state) | Lifecycle rule deletes after 90 days | **< $0.01** |
| S3 API calls | 2,000 PUT / 20,000 GET free per month | **$0.00** under normal usage |
| DynamoDB table | PAY_PER_REQUEST; 25 WCU + 25 RCU free/month | **$0.00** under normal usage |
| DynamoDB storage | 25 GB free per month | **$0.00** |
| App S3 bucket (infra) | Empty bucket, no objects stored | **$0.00** |

**Total estimated cost: $0.00 / month** for a typical development workflow.

> **Note:** Costs only materialise if you store gigabytes of data in the app bucket or run thousands of Terraform operations per day. Neither applies to a proof-of-concept.

---

## Prerequisites

| Requirement | Minimum version | Notes |
|-------------|-----------------|-------|
| Terraform CLI | 1.5.0 | Required for the `validation` blocks used in variables |
| AWS CLI | 2.x | For local credential configuration |
| AWS account | — | Free tier is sufficient |
| env0 account | — | Free tier available at [env0.com](https://www.env0.com) |
| Git repository | — | GitHub, GitLab, Bitbucket, or Azure DevOps |

---

## Step-by-Step Setup Guide

### Phase 1 — AWS Credentials

You need an IAM user or role that Terraform can assume. **Least-privilege** is enforced via the `iam-policy.json` file in this repo.

#### Option A — IAM User with static keys (simple, dev only)

1. In the AWS Console → **IAM** → **Users** → **Create user**.
2. Name it `terraform-env0`.
3. Attach a custom policy — paste the contents of `iam-policy.json`.
4. Create an **Access Key** under the Security Credentials tab.
5. Note the `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.

#### Option B — IAM Role with OIDC (recommended for production)

env0 supports AWS OIDC. Under **Organisation Settings → Cloud Credentials → AWS**, create an OIDC credential. env0 will assume the role directly without static keys.

See env0 docs: https://docs.env0.com/docs/aws-credentials

---

### Phase 2 — Run the Bootstrap Workspace

The bootstrap workspace must run **once** before anything else.

#### Option A — Run locally (fastest)

```bash
cd bootstrap

# Authenticate (choose one)
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
# -- or --
aws configure

# Initialise (local backend — no remote config needed yet)
terraform init

# Preview
terraform plan

# Apply — this creates the S3 bucket and DynamoDB table
terraform apply
```

After a successful apply, **copy the `backend_hcl_snippet` output**. It looks like this:

```
backend_hcl_snippet = <<EOT

  # infra/backend.hcl — generated by bootstrap outputs
  bucket         = "tf-remote-backend-state-123456789012-eu-central-1"
  key            = "infra/terraform.tfstate"
  region         = "eu-central-1"
  dynamodb_table = "tf-remote-backend-locks"
  encrypt        = true
EOT
```

#### Option B — Run via env0

1. Push this repo to your Git provider.
2. Create a new env0 environment, point it at the `bootstrap` directory.
3. Set the AWS credentials (see env0 Cloud Credentials or env vars).
4. Click **Deploy**.
5. After success, view the run outputs and note the `backend_hcl_snippet` value.

---

### Phase 3 — Configure the Infra Backend

Open `infra/backend.hcl` and replace `<ACCOUNT_ID>` with your 12-digit AWS account ID (shown in the bootstrap output `aws_account_id`):

```hcl
# Before
bucket = "tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1"

# After
bucket = "tf-remote-backend-state-123456789012-eu-central-1"
```

Commit and push `infra/backend.hcl`.

To verify locally:

```bash
cd infra
terraform init -backend-config=backend.hcl
```

You should see:

```
Initializing the backend...
Successfully configured the backend "s3"!
```

---

### Phase 4 — Connect to env0

1. Log in to [app.env0.com](https://app.env0.com).
2. Create a **Project** named `terraform-s3-remote-backend` (must match `projectName` in `env0.yml`).
3. Connect your Git repository under **Settings → VCS**.
4. env0 will auto-detect `env0.yml` and offer to import the two environments.

#### Configure AWS credentials in env0

**Via Cloud Credentials (OIDC — recommended):**
- Go to **Organisation Settings → Cloud Credentials**.
- Create an AWS credential, choosing OIDC or static key type.
- Assign it to the `terraform-s3-remote-backend` project.

**Via Environment Variables (quick option):**
- In each environment's **Configuration** tab, add:
  - `AWS_ACCESS_KEY_ID` (mark as sensitive)
  - `AWS_SECRET_ACCESS_KEY` (mark as sensitive)

---

### Phase 5 — Deploy via env0

#### Deploy bootstrap (first time only)

1. Open the **Remote Backend - Bootstrap** environment.
2. Click **Deploy** → review the plan → **Approve**.
3. Verify the outputs include `state_bucket_name` and `dynamodb_table_name`.

#### Deploy infra (every subsequent deploy)

1. Open the **Remote Backend - Infra** environment.
2. Confirm the **Terraform Init Arguments** field is set to `-backend-config=backend.hcl`.
3. Click **Deploy** → review the plan → **Approve**.
4. After success, the `app_bucket_name` output shows the created S3 bucket.

---

## IAM Permissions

`iam-policy.json` covers the **minimum required permissions**:

| Statement | What it allows |
|-----------|---------------|
| `TerraformStateS3` | Read/write/list state files in the backend bucket |
| `TerraformDynamoDBLock` | Acquire and release state locks |
| `BootstrapCreateBackendResources` | Create/delete the backend S3 bucket and DynamoDB table (bootstrap workspace only) |
| `InfraAppBucketCRUD` | Create/configure the application S3 bucket (infra workspace only) |
| `GetCallerIdentity` | Lets Terraform resolve the account ID (used in resource name locals) |

> **Tip:** In a real project, split this into two separate policies — one for the bootstrap IAM user/role and one for the infra IAM user/role — so the infra executor cannot modify the backend resources.

---

## env0 Configuration Deep Dive

### env0.yml structure

```yaml
version: 2

environments:
  <env-key>:
    name: "Human readable name"
    projectName: "Must match env0 Project"
    workspace: "Terraform workspace name"
    terraformVersion: "1.9.0"
    autoApprove: false        # Require manual plan approval
    root:
      directory: <path>       # Which folder to run Terraform from
      terraformInit:
        additionalArguments: "-backend-config=backend.hcl"
    environmentVariables:
      - name: TF_VAR_foo      # Becomes var.foo in Terraform
        value: "bar"
      - name: SECRET_VAR
        sensitive: true       # Hidden in logs and UI
```

### Partial backend configuration

The `infra` workspace uses Terraform's **partial configuration** pattern:

- `infra/backend.tf` contains an empty `backend "s3" {}` block.
- `infra/backend.hcl` contains the actual bucket/table values.
- At `terraform init`, the `-backend-config=backend.hcl` flag merges them.

This avoids hardcoding account IDs in version-controlled Terraform code and makes it trivial to point the same code at a different backend (e.g. for a different AWS account or region).

### Passing backend config without a file

If you prefer not to commit `backend.hcl`, supply each value via env0 environment variables using `TF_CLI_ARGS_init`:

```
TF_CLI_ARGS_init = -backend-config="bucket=tf-remote-backend-state-123456789012-eu-central-1" -backend-config="key=infra/terraform.tfstate" -backend-config="region=eu-central-1" -backend-config="dynamodb_table=tf-remote-backend-locks" -backend-config="encrypt=true"
```

---

## Verifying the Remote Backend

After the infra workspace deploys successfully, confirm state is remote:

### 1. Check the S3 bucket

In the AWS Console → S3 → `tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1`:

You should see an object at the path:

```
infra/terraform.tfstate
```

Click the object → **Versions** to see that versioning is tracking each apply.

### 2. Watch a lock being acquired

Run a plan locally in a separate terminal while an apply is in progress:

```bash
cd infra
terraform plan
```

Terraform will print:

```
Acquiring state lock. This may take a few moments...
Error: Error acquiring the state lock
  Lock Info:
    ID:        <uuid>
    Path:      tf-remote-backend-state-.../infra/terraform.tfstate
    Operation: OperationTypeApply
    Who:       <user>@<host>
    Created:   <timestamp>
```

This confirms DynamoDB locking is working.

### 3. Inspect the DynamoDB lock table

In the AWS Console → DynamoDB → Tables → `tf-remote-backend-locks` → **Explore table items**.

During an active apply you will see a single item with the `LockID` matching the S3 key. After the apply completes the item is deleted automatically.

---

## Teardown

> **Warning:** Destroying the bootstrap workspace will delete the S3 bucket that stores the infra state. Always destroy the infra workspace first.

### Step 1 — Destroy infra

```bash
cd infra
terraform init -backend-config=backend.hcl
terraform destroy
```

Or click **Destroy** in the env0 infra environment.

### Step 2 — Empty the state bucket

The `prevent_destroy = true` lifecycle guard and S3 versioning mean you must manually empty the bucket before Terraform can delete it.

```bash
# Empty all current objects and all versions
aws s3 rm s3://tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1 --recursive
aws s3api delete-objects \
  --bucket tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1 \
  --delete "$(aws s3api list-object-versions \
    --bucket tf-remote-backend-state-<ACCOUNT_ID>-eu-central-1 \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json)"
```

### Step 3 — Remove the prevent_destroy guard

In `bootstrap/main.tf`, delete or comment out the lifecycle block:

```hcl
# lifecycle {
#   prevent_destroy = true
# }
```

### Step 4 — Destroy bootstrap

```bash
cd bootstrap
terraform destroy
```

---

## Troubleshooting

### `Error: Failed to get existing workspaces: AccessDenied`

The IAM identity used by Terraform does not have `s3:ListBucket` on the state bucket. Verify the `TerraformStateS3` IAM statement includes the bucket ARN without a trailing `/*`.

### `Error: Error acquiring the state lock` (stale lock)

A previous apply was interrupted and left a lock record in DynamoDB. To force-unlock:

```bash
cd infra
terraform force-unlock <LOCK_ID>
```

The `LOCK_ID` is printed in the error message. Only do this when you are certain no apply is running.

### `Error: No valid credential sources found`

Terraform cannot find AWS credentials. Ensure one of the following is set:
- `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` environment variables
- `~/.aws/credentials` file (via `aws configure`)
- Instance profile / OIDC role (in CI/CD)

### `BucketAlreadyExists` or `BucketAlreadyOwnedByYou`

S3 bucket names are globally unique. If the default project name clashes, change `TF_VAR_project_name` to a unique value before re-running bootstrap.

### env0: `Terraform Init failed — backend configuration changed`

This happens when backend.hcl values differ from the last `terraform init`. In env0, click **Reset Remote State** (or run `terraform init -reconfigure -backend-config=backend.hcl` locally) to re-initialise with the new values.

---

## Key Terraform Concepts Used

| Concept | Where used | Why |
|---------|-----------|-----|
| **Remote backend (S3)** | `infra/backend.tf` | Stores state in S3; enables team collaboration |
| **State locking (DynamoDB)** | `infra/backend.tf` | Prevents concurrent applies corrupting state |
| **Partial backend configuration** | `infra/backend.hcl` + `terraform init -backend-config` | Keeps account IDs out of the main codebase |
| **`prevent_destroy` lifecycle** | `bootstrap/main.tf` | Prevents accidental deletion of the state bucket |
| **`depends_on`** | `bootstrap/main.tf` | Ensures versioning is enabled before lifecycle rules apply |
| **`PAY_PER_REQUEST` DynamoDB** | `bootstrap/main.tf` | Eliminates provisioned capacity cost |
| **S3 bucket lifecycle rules** | `bootstrap/main.tf` | Expires old state versions after 90 days to limit storage cost |
| **`default_tags`** | Both `providers.tf` files | Applies consistent tags to all resources without repetition |
| **Input validation** | Both `variables.tf` files | Fails fast with clear errors if variables are misconfigured |
