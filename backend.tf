terraform {
  backend "s3" {
    bucket = "traning-usecases"
    key    = "hello-world-app/terraform.tfstate"
    region = "us-east-1"
  }
}
