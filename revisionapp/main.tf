module "vpc" {
  source  = "./modules/vpc"
  project = var.vpc_project
  region  = var.vpc_region
}

module "resource" {
  source                    = "./modules/eks"
  private_subnet_ids        = module.vpc.private_subnet_ids
  public_subnet_ids         = module.vpc.public_subnet_ids
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  vpc_id                    = module.vpc.vpc_id
  project                   = var.resource_project
  region                    = var.resource_region
}

module "lambda" {
  source             = "./modules/lambda"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = []
  project            = var.lambda_project
  region             = var.lambda_region
  runtime            = var.lambda_runtime
}

module "ec2" {
  source         = "./modules/ec2"
  cluster_name   = module.resource.cluster_name
  subnet_ids     = module.vpc.private_subnet_ids
  desired_size   = var.ec2_desired_size
  instance_types = var.ec2_instance_types
  max_size       = var.ec2_max_size
  min_size       = var.ec2_min_size
  project        = var.ec2_project
  region         = var.ec2_region
}

module "alb" {
  source            = "./modules/alb"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  project           = var.alb_project
  region            = var.alb_region
}

module "elasticache" {
  source           = "./modules/elasticache"
  vpc_id           = module.vpc.vpc_id
  cache_subnet_ids = module.vpc.private_subnet_ids
  ha               = var.elasticache_ha
  project          = var.elasticache_project
  region           = var.elasticache_region
  replicas         = var.elasticache_replicas
}

module "s3" {
  source  = "./modules/s3"
  project = var.s3_project
  region  = var.s3_region
}

module "dynamodb" {
  source       = "./modules/dynamodb"
  billing_mode = var.dynamodb_billing_mode
  project      = var.dynamodb_project
  region       = var.dynamodb_region
}

module "cloudfront" {
  source               = "./modules/cloudfront"
  origin_type          = "http"
  custom_origin_domain = module.alb.alb_dns_name
  web_acl_id           = module.waf.web_acl_arn
  project              = var.cloudfront_project
  region               = var.cloudfront_region
}

module "waf" {
  source    = "./modules/waf"
  providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }
  scope     = "CLOUDFRONT"
  region    = "us-east-1"
  project   = var.waf_project
}

module "cloudwatchlogs" {
  source  = "./modules/cloudwatchlogs"
  project = var.cloudwatchlogs_project
  region  = var.cloudwatchlogs_region
}

module "cloudwatchmonitoring" {
  source           = "./modules/cloudwatchmonitoring"
  alb_arn_suffixes = [module.alb.alb_arn_suffix]
  sqs_queue_arns   = [module.sqs.queue_arn]
  project          = var.cloudwatchmonitoring_project
  region           = var.cloudwatchmonitoring_region
}

module "cognito" {
  source       = "./modules/cognito"
  mfa_required = var.cognito_mfa_required
  project      = var.cognito_project
  region       = var.cognito_region
  sign_in_type = var.cognito_sign_in_type
}

module "apigateway" {
  source  = "./modules/apigateway"
  project = var.apigateway_project
  region  = var.apigateway_region
}

module "kms" {
  source  = "./modules/kms"
  project = var.kms_project
  region  = var.kms_region
}

module "secretsmanager" {
  source  = "./modules/secretsmanager"
  project = var.secretsmanager_project
  region  = var.secretsmanager_region
}

module "opensearch" {
  source     = "./modules/opensearch"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  project    = var.opensearch_project
  region     = var.opensearch_region
}

module "bedrock" {
  source         = "./modules/bedrock"
  s3_bucket_arn  = module.s3.bucket_arn
  opensearch_arn = module.opensearch.opensearch_arn
  project        = var.bedrock_project
  region         = var.bedrock_region
}

module "sqs" {
  source  = "./modules/sqs"
  project = var.sqs_project
  region  = var.sqs_region
}

module "githubactions" {
  source  = "./modules/githubactions"
  project = var.githubactions_project
}
