provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "personal_website"
      Owner       = "Samuel"
      Provisioner = "Terraform"
    }
  }
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.82.0"
    }
  }
  required_version = "1.10.3"
}