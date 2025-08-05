provider "aws" {
  region = "us-east-1"
}

provider "auth0" {
  domain        = "dev-gfew5m8jtuzrrhhw.us.auth0.com"
  client_id                  = "3ECMEpuEMGFl4ikPkSanEbo2zYT2G3hm"
  client_secret              = "ZakrXm0SMESE3shtS2koXVWgHm77IccGEQz08f6vbeCKdW90blcp2mmt4vq7C5EN"
}

# S3 Bucket for Hosting
resource "aws_s3_bucket" "website_bucket" {
  bucket = "hello-world-web-app-prod"

  tags = {
    Name = "HelloWorldWebAppProd"
  }
}

resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = aws_s3_bucket.website_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "website_bucket_block" {
  bucket = aws_s3_bucket.website_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "website_policy" {
  bucket = aws_s3_bucket.website_bucket.id

  depends_on = [aws_s3_bucket_public_access_block.website_bucket_block]

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicReadGetObject",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.website_bucket.arn}/*"
      }
    ]
  })
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "website_distribution" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.website_config.website_endpoint
    origin_id   = "S3Origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "HelloWorldWebAppDistribution"
  }
}

# Auth0 Application Configuration
resource "auth0_client" "hello_world_app" {
  name            = "HelloWorldApp"
  app_type        = "regular_web"
  callbacks       = ["https://${aws_cloudfront_distribution.website_distribution.domain_name}/index.html"]
  logout_urls     = ["https://${aws_cloudfront_distribution.website_distribution.domain_name}/logout"]
  oidc_conformant = true
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "hello-world-user-pool"
}

# Auth0 Identity Provider for Cognito
resource "aws_cognito_identity_provider" "auth0" {
  user_pool_id  = aws_cognito_user_pool.user_pool.id
  provider_name = "Auth0"
  provider_type = "OIDC"

  provider_details = {
    client_id                  = "3ECMEpuEMGFl4ikPkSanEbo2zYT2G3hm"
    client_secret              = "ZakrXm0SMESE3shtS2koXVWgHm77IccGEQz08f6vbeCKdW90blcp2mmt4vq7C5EN"
    authorize_scopes           = "openid email profile"
    oidc_issuer                = "https://dev-gfew5m8jtuzrrhhw.us.auth0.com"
    attributes_request_method  = "GET"
  }

  attribute_mapping = {
    email = "email"
    name  = "name"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "hello-world-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "openid", "profile"]

  callback_urls = [
    "https://${aws_cloudfront_distribution.website_distribution.domain_name}/index.html"
  ]

  logout_urls = [
    "https://${aws_cloudfront_distribution.website_distribution.domain_name}/logout"
  ]

  supported_identity_providers = ["COGNITO", "Auth0"]

  depends_on = [
    aws_cognito_user_pool.user_pool,
    aws_cognito_identity_provider.auth0
  ]
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "hello-world-app-prod-domain"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "hello-world-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Effect = "Allow",
      Sid    = ""
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "hello_world" {
  function_name = "hello-world-function"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"

  filename         = "${path.module}/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda.zip")
}

# API Gateway Setup
resource "aws_api_gateway_rest_api" "hello_api" {
  name        = "hello-world-api"
  description = "API for Hello World Lambda"
}

resource "aws_api_gateway_resource" "hello_resource" {
  rest_api_id = aws_api_gateway_rest_api.hello_api.id
  parent_id   = aws_api_gateway_rest_api.hello_api.root_resource_id
  path_part   = "hello"
}

resource "aws_api_gateway_authorizer" "cognito_auth" {
  name                    = "CognitoAuthorizer"
  rest_api_id             = aws_api_gateway_rest_api.hello_api.id
  identity_source         = "method.request.header.Authorization"
  type                    = "COGNITO_USER_POOLS"
  provider_arns           = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_method" "hello_method" {
  rest_api_id   = aws_api_gateway_rest_api.hello_api.id
  resource_id   = aws_api_gateway_resource.hello_resource.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_auth.id
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.hello_api.id
  resource_id             = aws_api_gateway_resource.hello_resource.id
  http_method             = aws_api_gateway_method.hello_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.hello_world.invoke_arn
}

resource "aws_api_gateway_deployment" "hello_deployment" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.hello_api.id
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.hello_api.id
  deployment_id = aws_api_gateway_deployment.hello_deployment.id

  variables = {
    lambdaAlias = "prod"
  }

  tags = {
    Environment = "prod"
  }
}

# Outputs
output "api_invoke_url" {
  value = "https://${aws_api_gateway_rest_api.hello_api.id}.execute-api.us-east-1.amazonaws.com/prod/hello"
}

output "cognito_login_url" {
  value = "https://hello-world-app-prod-domain.auth.us-east-1.amazoncognito.com/login?response_type=token&client_id=${aws_cognito_user_pool_client.user_pool_client.id}&redirect_uri=https://${aws_cloudfront_distribution.website_distribution.domain_name}/index.html"
}
