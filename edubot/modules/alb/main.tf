terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

# The VPC's CIDR bounds the ALB's egress (see the egress rule below).
data "aws_vpc" "this" {
  id = var.vpc_id
}

# Security group for the public ALB
resource "aws_security_group" "alb_sg" {
  name        = "${var.project}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  # HTTP
  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allow_cidrs
  }

  # HTTPS (always open; listener is conditional)
  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allow_cidrs
  }

  # Outbound: only to the targets, on the target port. An ALB opens
  # connections only to its targets and their health checks (both on
  # var.target_port, the "traffic-port" default), and every target is in
  # this VPC; it never needs to reach the internet. A Lambda target is
  # invoked through the Lambda API, not through this rule. Leaving egress
  # open to 0.0.0.0/0 would let a compromised or misrouted ALB reach any
  # address (Trivy AWS-0104).
  egress {
    description = "To targets in the VPC"
    from_port   = var.target_port
    to_port     = var.target_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

  tags = merge({ Name = "${var.project}-alb-sg" }, var.tags)
}

# Internet-facing ALB
resource "aws_lb" "alb" {
  name               = "${var.project}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  # Drop requests whose header names are not valid HTTP. Targets would
  # otherwise get headers that a proxy and an app parse differently, the
  # raw material of request smuggling (Trivy AWS-0052).
  drop_invalid_header_fields = true

  tags = merge({ Name = "${var.project}-alb" }, var.tags)
}

# Default target group (attach ECS/EKS/instances later)
resource "aws_lb_target_group" "app" {
  name        = "${var.project}-tg"
  vpc_id      = var.vpc_id
  port        = var.target_port
  protocol    = var.target_protocol
  target_type = var.target_type

  health_check {
    enabled             = true
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    path                = var.health_check_path
    protocol            = var.health_check_protocol
    matcher             = "200-399"
  }

  tags = merge({ Name = "${var.project}-tg" }, var.tags)
}

# HTTP listener → forward (when no cert)
resource "aws_lb_listener" "http_forward" {
  count             = var.certificate_arn == null ? 1 : 0
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# HTTP listener → redirect to HTTPS (when cert provided)
resource "aws_lb_listener" "http_redirect" {
  count             = var.certificate_arn == null ? 0 : 1
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener (when cert provided)
resource "aws_lb_listener" "https" {
  count             = var.certificate_arn == null ? 0 : 1
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  # TLS 1.2 and 1.3 only, forward-secret ciphers. The 2016-08 policy still
  # allowed TLS 1.0 and 1.1.
  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
