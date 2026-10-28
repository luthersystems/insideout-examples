# The VPC's CIDR bounds who may reach the domain (see the ingress rule).
data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_security_group" "opensearch" {
  name        = "${var.project}-opensearch-sg"
  description = "Security group for OpenSearch domain"
  vpc_id      = var.vpc_id

  # HTTPS from inside the VPC only. The domain sits in a private subnet, so
  # the stack's own clients (Lambda, EC2) reach it from inside the VPC.
  ingress {
    description = "HTTPS from the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

  # No egress on purpose. For search and indexing the domain only answers
  # requests that arrive on 443; it does not need to open connections
  # through its VPC interfaces. An empty list makes Terraform delete the
  # allow-all rule AWS adds to a new group, and the old 0.0.0.0/0 rule on a
  # group made before this change, so the domain's interfaces cannot be used
  # to reach the internet (Trivy AWS-0104). Leaving egress out would keep
  # that old rule.
  egress = []

  tags = {
    Name = "${var.project}-opensearch-sg"
  }
}

resource "aws_opensearch_domain" "managed" {
  count = var.deployment_type == "managed" ? 1 : 0

  domain_name    = "${var.project}-search"
  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type          = var.instance_type
    instance_count         = var.multi_az ? 2 : 1
    zone_awareness_enabled = var.multi_az
  }

  ebs_options {
    ebs_enabled = true
    volume_size = tonumber(replace(var.storage_size, "GB", ""))
    volume_type = "gp3"
  }

  vpc_options {
    subnet_ids         = [var.subnet_ids[0]]
    security_group_ids = [aws_security_group.opensearch.id]
  }

  # Encrypt indices, logs, swap and automated snapshots on disk with the
  # AWS managed key aws/es (Trivy AWS-0048). Turning it on later forces a
  # blue/green update of the domain, so it is on from the first apply.
  encrypt_at_rest {
    enabled = true
  }

  # Encrypt traffic between the domain's nodes with TLS (Trivy AWS-0043).
  # Like encryption at rest, turning it on later forces a blue/green update.
  node_to_node_encryption {
    enabled = true
  }

  # Refuse plain HTTP on the endpoint (Trivy AWS-0046) and accept only
  # TLS 1.2 or later with forward-secret ciphers (Trivy AWS-0126). The
  # domain holds the app's search data, so it must not be readable on the
  # wire.
  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-PFS-2023-10"
  }

  tags = {
    Domain = "${var.project}-search"
  }
}

resource "aws_opensearchserverless_collection" "serverless" {
  count = var.deployment_type == "serverless" ? 1 : 0

  name = "${var.project}-search"
  type = "VECTORSEARCH"

  tags = {
    Name = "${var.project}-search"
  }
}

