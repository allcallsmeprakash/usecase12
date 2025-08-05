terraform {
  backend "s3" {
    bucket = "training-usecases"
    key    = "hello-world-app/terraform.tfstate"
    region = "us-east-1"
  }
}
