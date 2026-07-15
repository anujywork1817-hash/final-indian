# Deploying kumbh_backend to AWS Elastic Beanstalk

This backend deploys as one multi-container Docker Compose environment
(EB's "Docker running on 64-bit Amazon Linux 2023" platform runs
`docker-compose.yml` directly — no ECS/Dockerrun.aws.json needed).

Local Postgres container is skipped in this environment (it's gated
behind the `local` Compose profile — see `.env`); production uses an
RDS Postgres instance instead, wired in via `DATABASE_URL`.

## 0. Prerequisites

```bash
# AWS CLI
winget install Amazon.AWSCLI      # or https://awscli.amazonaws.com/AWSCLIV2.msi

# EB CLI (needs Python)
pip install awsebcli --upgrade --user

aws configure     # Access Key ID, Secret Access Key, region (e.g. ap-south-1)
```

## 1. Create the RDS Postgres instance

```bash
aws rds create-db-instance \
  --db-instance-identifier kumbh-tent-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 15.4 \
  --master-username postgres \
  --master-user-password "CHOOSE_A_STRONG_PASSWORD" \
  --allocated-storage 20 \
  --db-name kumbh_tent \
  --publicly-accessible \
  --backup-retention-period 7

aws rds wait db-instance-available --db-instance-identifier kumbh-tent-db

aws rds describe-db-instances \
  --db-instance-identifier kumbh-tent-db \
  --query "DBInstances[0].Endpoint.Address" --output text
```

`--publicly-accessible` is only so you can run the schema import from your
laptop in the next step. After the app is deployed (step 5), lock the RDS
security group down to only accept 5432 from the EB environment's EC2
security group and remove public access.

## 2. Load the schema

Temporarily allow your current IP in the RDS security group (console →
RDS → your instance → Connectivity & security → security group → Edit
inbound rules → add your IP on port 5432), then:

```bash
psql "postgresql://postgres:CHOOSE_A_STRONG_PASSWORD@<RDS_ENDPOINT>:5432/kumbh_tent?sslmode=require" \
  -f schema.sql
```

## 3. Initialize Elastic Beanstalk

From this directory (`kumbh_backend/`):

```bash
eb init -p "Docker running on 64bit Amazon Linux 2023" kumbh-backend --region ap-south-1
```

## 4. Create the environment with real secrets

Fill in the values below (see `.env.aws.example` for the full list and
what each one means). Generate a fresh `JWT_SECRET` — don't reuse the
local dev value, and don't reuse Razorpay *test* keys for anything that
takes real payments.

```bash
eb create kumbh-backend-prod \
  --envvars DATABASE_URL="postgresql://postgres:CHOOSE_A_STRONG_PASSWORD@<RDS_ENDPOINT>:5432/kumbh_tent?sslmode=require",JWT_SECRET="<LONG_RANDOM_SECRET>",RAZORPAY_KEY_ID="<KEY>",RAZORPAY_KEY_SECRET="<SECRET>",GATEWAY_PORT=80
```

This can take several minutes the first time (building 5 Go images).

## 5. Get the URL and lock down RDS

```bash
eb status kumbh-backend-prod
```

Take the environment's CNAME/URL and:
- Update `kumbh_tent/lib/core/network/api_service.dart` (`baseUrl`) and
  `kumbh_tent/lib/core/constants/constants.dart` (`kBaseUrl`) to point at
  `http://<eb-env-url>/api/v1` (or set up HTTPS via ACM + the EB load
  balancer for a real production rollout — plain HTTP is fine for testing
  only).
- In the RDS console, edit the security group to remove the public/your-IP
  inbound rule and instead allow port 5432 only from the EB environment's
  EC2 security group (Environment → Configuration → Instances → EC2
  security groups).

## 6. Subsequent deploys

```bash
eb deploy kumbh-backend-prod
```

## Notes

- `auth-service`, `tent-service`, `booking-service`, `payment-service`
  ports (8081-8084) are still published on the instance for direct
  debugging, same as local dev. Only `api-gateway` (port 80, set via
  `GATEWAY_PORT`) needs to be reachable from the internet — consider
  restricting the EB instance security group to just port 80/443 once
  you've confirmed everything works.
- `firebase-service-account.json` (booking-service, payment-service) is
  bundled into the deploy via `.ebignore` (which, unlike `.gitignore`,
  does not exclude `*.json`). If you rotate this credential, replace the
  file locally before your next `eb deploy`.
- Health check: `.ebextensions/healthcheck.config` points EB's health
  check at `/health` on port 80 (the gateway's health route) instead of
  the default `/`, which the gateway doesn't serve.
