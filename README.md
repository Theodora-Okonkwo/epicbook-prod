# EpicBook — AWS Two-Tier Deployment

A production-style deployment of **EpicBook**, a Node.js/Express bookstore web application, on AWS using **Terraform** for infrastructure provisioning and **Ansible roles** for configuration management and deployment.

---

## Architecture

```
Internet
    │
    ▼
[Elastic IP]
    │
    ▼
[EC2 - Ubuntu 22.04]  ── Public Subnet (10.0.1.0/24)
 Nginx :80
 Node.js :8080 (PM2)
    │
    │ MySQL :3306
    ▼
[RDS MySQL 8.0]  ── Private Subnets (10.0.2.0/24, 10.0.3.0/24)
```

- **Tier 1 (Application):** EC2 instance running Node.js/Express behind Nginx reverse proxy, managed by PM2
- **Tier 2 (Data):** RDS MySQL 8.0 in private subnets — not accessible from the internet

---

## Folder Structure

```
epicbook-prod/
├── terraform/
│   └── aws/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── terraform.tfvars        # ⚠️ not committed — see setup below
│       └── .gitignore
└── ansible/
    ├── inventory.ini
    ├── site.yml
    ├── group_vars/
    │   └── web.yml                 # ⚠️ secrets replaced with placeholders
    └── roles/
        ├── common/
        │   ├── tasks/main.yml
        │   └── handlers/main.yml
        ├── nodejs/
        │   ├── tasks/main.yml
        │   └── handlers/main.yml
        ├── epicbook/
        │   ├── tasks/main.yml
        │   ├── handlers/main.yml
        │   └── templates/
        │       ├── config.json.j2
        │       └── dotenv.j2
        └── nginx/
            ├── tasks/main.yml
            ├── handlers/main.yml
            └── templates/
                └── epicbook.conf.j2
```

---

## Prerequisites

| Tool      | Version  |
|-----------|----------|
| Terraform | >= 1.3.0 |
| Ansible   | >= 2.12  |
| AWS CLI   | v2       |
| Python3   | >= 3.8   |

---

## Setup

### 1. Clone this repository

```bash
git clone <your-repo-url>
cd epicbook-prod
```

### 2. Configure AWS credentials

```bash
aws configure
```

```
AWS Access Key ID:     <your access key>
AWS Secret Access Key: <your secret key>
Default region name:   us-east-1
Default output format: json
```

### 3. Create terraform.tfvars

This file is **not committed** to the repo. Create it manually:

```bash
cat > terraform/aws/terraform.tfvars << EOF
aws_region  = "us-east-1"
db_name     = "bookstore"
db_username = "<your_db_username>"
db_password = "<your_db_password>"
EOF
```

> ⚠️ Never commit `terraform.tfvars` — it contains your database password.

---

## Deployment

### Step 1 — Provision Infrastructure

```bash
cd terraform/aws
terraform init
terraform plan
terraform apply
```

Note the outputs:

```
public_ip    = "<ec2_public_ip>"
admin_user   = "ubuntu"
rds_endpoint = "<rds_hostname>"
app_url      = "http://<ec2_public_ip>"
```

### Step 2 — Prepare SSH Key

```bash
cp terraform/aws/epicbook-key.pem ~/.ssh/epicbook-key.pem
chmod 400 ~/.ssh/epicbook-key.pem
```

### Step 3 — Test SSH Access

```bash
ssh -i ~/.ssh/epicbook-key.pem ubuntu@<public_ip> 'hostname'
```

### Step 4 — Configure Ansible

Update `ansible/inventory.ini` with your EC2 public IP:

```ini
[web]
<public_ip>

[web:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/epicbook-key.pem
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

Update `ansible/group_vars/web.yml` with your RDS endpoint and credentials:

```yaml
app_repo: "https://github.com/pravinmishraaws/theepicbook"
app_dest: "/home/ubuntu/theepicbook"
app_user: "ubuntu"
app_port: 8080

db_host: "<rds_endpoint from terraform output>"
db_name: "bookstore"
db_user: "<your_db_username>"
db_password: "<your_db_password>"
```

### Step 5 — Run Ansible Playbook

```bash
cd ansible

# Test connectivity
ansible web -i inventory.ini -m ping

# Deploy
ansible-playbook -i inventory.ini site.yml
```

### Step 6 — Open in Browser

```
http://<public_ip>
```

---

## Ansible Roles

| Role | Purpose |
|------|---------|
| **common** | Updates packages, installs baseline tools, hardens SSH |
| **nodejs** | Installs NVM, Node.js 18 and PM2 |
| **epicbook** | Clones repo, installs dependencies, writes DB config, seeds database, starts app with PM2 |
| **nginx** | Installs Nginx, configures reverse proxy from port 80 to 8080 |

Roles run in order: `common → nodejs → epicbook → nginx`

---

## What Terraform Provisions

| Resource | Details |
|----------|---------|
| VPC | 10.0.0.0/16 |
| Public Subnet | 10.0.1.0/24 — EC2 |
| Private Subnet A | 10.0.2.0/24 — RDS |
| Private Subnet B | 10.0.3.0/24 — RDS |
| Internet Gateway | Routes public traffic |
| Route Table | 0.0.0.0/0 → IGW |
| EC2 Security Group | Inbound: SSH (22), HTTP (80) |
| RDS Security Group | Inbound: MySQL (3306) from EC2 only |
| EC2 Instance | t3.micro, Ubuntu 22.04 |
| Elastic IP | Static public IP |
| RDS MySQL | db.t3.micro, MySQL 8.0, private subnets |

---

## Verification

```bash
# Check app is running
ssh -i ~/.ssh/epicbook-key.pem ubuntu@<public_ip> 'pm2 status'

# Check app logs
ssh -i ~/.ssh/epicbook-key.pem ubuntu@<public_ip> 'pm2 logs epicbook --lines 50 --nostream'

# Check Nginx config
ssh -i ~/.ssh/epicbook-key.pem ubuntu@<public_ip> 'cat /etc/nginx/sites-available/epicbook'

# Check Nginx status
ssh -i ~/.ssh/epicbook-key.pem ubuntu@<public_ip> 'sudo systemctl status nginx'
```

---

## Idempotency

Re-running the playbook is safe — most tasks will show `ok` instead of `changed`:

```bash
ansible-playbook -i inventory.ini site.yml
```

Expected PLAY RECAP on re-run:
```
<public_ip> : ok=31  changed=0  unreachable=0  failed=0  skipped=0
```

---

## Cleanup

To destroy all AWS resources and avoid charges:

```bash
cd terraform/aws
terraform destroy
```

> ⚠️ This permanently deletes EC2, RDS, VPC and all associated resources.

---

## .gitignore

The following are excluded from version control:

```
# Terraform
.terraform/
.terraform.lock.hcl
terraform.tfstate
terraform.tfstate.backup
terraform.tfvars        # contains DB password
epicbook-key.pem        # private SSH key

# Ansible
ansible/group_vars/web.yml   # contains DB credentials
ansible/inventory.ini        # contains server IP
```

---

## Tech Stack

- **Cloud:** AWS (EC2, RDS, VPC, EIP)
- **IaC:** Terraform >= 1.3.0
- **Config Management:** Ansible
- **Runtime:** Node.js 18, PM2
- **Web Server:** Nginx
- **Database:** MySQL 8.0
- **App:** Express.js + Sequelize + Handlebars