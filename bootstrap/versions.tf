terraform {
  required_version = ">= 1.10" # S3 상태 잠금(use_lockfile)을 쓰려면 1.10 이상

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  
  # 상태는 자기가 만든 버킷에 둔다. 공통 값은 envs/dev/backend.hcl 에서 받는다.
  #   terraform init "-backend-config=../envs/dev/backend.hcl"
  # 새 계정에서 처음 만들 때: 버킷이 없으므로 이 블록을 잠시 주석 처리 → 로컬로 apply
  #   → 주석을 풀고 init -migrate-state 로 상태를 버킷에 옮긴다.

  backend "s3" {
    key = "bootstrap/terraform.tfstate" # 이 스택의 상태 위치
  }
}


provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}
