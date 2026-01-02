module "vpc" {
  source  = "./modules/vpc"
  project = var.vpc_project
  region  = var.vpc_region
}

module "lambda" {
  source             = "./modules/lambda"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = []
  region             = var.lambda_region
  runtime            = var.lambda_runtime
  timeout            = var.lambda_timeout
  memory_size        = var.lambda_memory_size
  project            = var.lambda_project
}

module "alb" {
  source            = "./modules/alb"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  project           = var.alb_project
  region            = var.alb_region
}

module "s3" {
  source     = "./modules/s3"
  project    = var.s3_project
  region     = var.s3_region
  versioning = var.s3_versioning
}

module "cloudfront" {
  source               = "./modules/cloudfront"
  custom_origin_domain = module.alb.alb_dns_name
  origin_type          = "http"
  project              = var.cloudfront_project
  region               = var.cloudfront_region
}

module "backups" {
  source          = "./modules/backups"
  enable_ec2_ebs  = false
  enable_rds      = true
  enable_dynamodb = false
  enable_s3       = false
  ec2_ebs_rule = {
    selection = {
      resource_arns  = []
      selection_tags = [{ type = "STRINGEQUALS", key = "backup", value = "true" }]
    }
  }
  default_rule = var.backups_default_rule
  project      = var.backups_project
  region       = var.backups_region
}

module "cloudwatchlogs" {
  source  = "./modules/cloudwatchlogs"
  project = var.cloudwatchlogs_project
  region  = var.cloudwatchlogs_region
}

module "cognito" {
  source       = "./modules/cognito"
  region       = var.cognito_region
  sign_in_type = var.cognito_sign_in_type
  project      = var.cognito_project
}

module "apigateway" {
  source  = "./modules/apigateway"
  project = var.apigateway_project
  region  = var.apigateway_region
}

module "secretsmanager" {
  source      = "./modules/secretsmanager"
  num_secrets = var.secretsmanager_num_secrets
  project     = var.secretsmanager_project
  region      = var.secretsmanager_region
}

module "githubactions" {
  source  = "./modules/githubactions"
  project = var.githubactions_project
}
