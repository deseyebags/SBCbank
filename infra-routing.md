# SBCbank Infrastructure Routing Overview

This document illustrates the routing flow through the SBCbank cloud-native infrastructure as defined in the Terraform configuration.

---

## High-Level Routing Diagram

```mermaid
graph TD
    Internet((Internet))
    CloudFront[CloudFront CDN]
    S3[S3 (Frontend SPA)]
    APIGW[API Gateway (HTTP API)]
    ALB[Application Load Balancer]
    ECS[ECS Fargate (Microservices)]
    RDS[(RDS PostgreSQL)]
    Redis[(ElastiCache Redis)]
    SQS[SQS Queues]

    Internet -->|HTTPS| CloudFront
    CloudFront -->|OAC| S3
    CloudFront -->|HTTPS| APIGW
    APIGW -->|HTTP| ALB
    ALB -->|HTTP| ECS
    ECS -->|TCP 5432| RDS
    ECS -->|TCP 6379| Redis
    ECS -->|SQS API| SQS
```

---

## Routing Pathways

### 1. Frontend (SPA)

- **User → CloudFront → S3**
  - Static assets are served from S3 via CloudFront with Origin Access Control (OAC).

### 2. API Requests

- **User → CloudFront → API Gateway → ALB → ECS (Microservices)**
  - API Gateway receives HTTP(S) requests, forwards to ALB, which routes to ECS tasks running microservices.

### 3. Database & Caching

- **ECS → RDS PostgreSQL**
  - ECS tasks in private subnets connect to RDS (also private) for data storage.
- **ECS → ElastiCache Redis**
  - ECS tasks use Redis for caching/session storage.

### 4. Messaging

- **ECS ↔ SQS**
  - Microservices communicate asynchronously via SQS queues (transactions, notifications).

---

## Subnet & Security Group Summary

- **Public Subnets:**
  - Host ALB, NAT Gateways, and allow inbound internet traffic.
- **Private Subnets:**
  - Host ECS tasks, RDS, and Redis. No direct internet access; outbound via NAT.
- **Security Groups:**
  - Strictly control traffic: ALB → ECS → RDS/Redis, with no public access to databases.

---

## Compliance Notes

- All resources are deployed in `ap-southeast-1` for MAS compliance.
- No public access to sensitive data stores.
- Encryption and network isolation enforced throughout.

---

For more details, see the Terraform files and [bankinfo.yaml](../bankinfo.yaml).
