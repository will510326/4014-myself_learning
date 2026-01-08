# 1. 告訴 Terraform 我們要用 AWS
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # 20260107
  backend "s3" {
    # 1. 剛剛建立的S3名稱
    bucket = "wayne-terraform-state-backend-20260107"

    # 2. 檔案要在S3裡面放哪裡(資料夾路徑)
    key = "global/s3/terraform.tfstate"

    # 3. region
    region = "ap-northeast-1"

    # 4. 鎖定用的table
    dynamodb_table = "terraform-locks"

    # 5. 加密
    encrypt = true
  }
}

# 2. 設定區域
provider "aws" {
  region = "ap-northeast-1"
}

# 抓取可用區域(例如1a, 1c)
data "aws_availability_zones" "available" {
  state = "available"
}

# 1. 建立VPC(圍牆)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16" # 你的地盤範圍(可以放65536個IP)
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "wayne-custom-vpc"
  }
}

# 2. 建立Internet Gateway(大門)
# 沒有這個，VPC就是一個封閉的孤島
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "wayne-igw"
  }
}
