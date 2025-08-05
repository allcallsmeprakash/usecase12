
provider "aws" {
  region = "us-east-1"
}

# S3 Bucket for Hosting
resource "aws_s3_bucket" "website_bucket" {
  bucket = "hello-world-web-app-prod"

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  tags = {
    Name = "HelloWorldWebAppProd"
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
    domain_name = aws_s3_bucket.website_bucket.website_endpoint
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
    Name = "HelloWorldWebAppDistributionProd"
  }
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "hello-world-user-pool-prod"
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "hello-world-client-prod"
  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows = ["code"]
  allowed_oauth_scopes = ["email", "openid", "profile"]
  callback_urls = ["https://hello-world-app-prod-domain.auth.us-east-1.amazoncognito.com/callback"]
  logout_urls   = ["https://hello-world-app-prod-domain.auth.us-east-1.amazoncognito.com/logout"]
  supported_identity_providers = ["COGNITO"]
}

# Cognito Hosted Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "hello-world-app-prod-domain"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# IAM Role for GitHub OIDC
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "github_oidc_role" {
  name = "github-actions-oidc-role-prod"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
            "token.actions.githubusercontent.com:sub": "repo:your-org/your-repo:ref:refs/heads/main"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_oidc_policy" {
  role       = aws_iam_role.github_oidc_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
