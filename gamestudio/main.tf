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
  memory_size        = var.lambda_memory_size
  project            = var.lambda_project
  region             = var.lambda_region
  runtime            = var.lambda_runtime
  timeout            = var.lambda_timeout
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
  region  = var.sqs_region
  project = var.sqs_project
}

module "githubactions" {
  source  = "./modules/githubactions"
  project = var.githubactions_project
}
