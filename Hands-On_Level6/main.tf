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

# 3. 建立Public Subnets(客廳)
# 我們建立2個，分別在不同區域(AZ)，為了高可用性
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"                                  # 分配一段IP
  availability_zone       = data.aws_availability_zones.available.names[0] # 東京1a
  map_public_ip_on_launch = true                                           # 重點！ 住在這裡的自動會有Public IP

  tags = { Name = "wayne-public-1" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"                                  # 分配一段IP
  availability_zone       = data.aws_availability_zones.available.names[1] # 東京1a
  map_public_ip_on_launch = true                                           # 重點！ 住在這裡的自動會有Public IP

  tags = { Name = "wayne-public-2" }
}

# 4. 建立Private Subnets(臥室)
# 一樣建立2個
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.101.0/24" # 故意跟Public分開遠一點
  availability_zone = data.aws_availability_zones.available.names[0]
  # 注意！這裡沒有map_public_ip_on_launch，預設是false(沒有公網IP)
  tags = { Name = "wayne=private-1" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.102.0/24" # 故意跟Public分開遠一點
  availability_zone = data.aws_availability_zones.available.names[1]
  # 注意！這裡沒有map_public_ip_on_launch，預設是false(沒有公網IP)
  tags = { Name = "wayne=private-2" }
}

# 5. 建立Elastic IP(固定IP) 給NAT Gateway用 !!!!這是要付錢的!!!! 一天1~2美金
resource "aws_eip" "nat" {
  domain = "vpc"
}

# 6. 建立NAT Gateway
# 他必須住在Public Subnet才能接觸外網
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id # 放在公有區1

  tags = { Name = "wayne-nat-gw" }

  # 確保IGW先建好，不然NAT會連不上網
  depends_on = [aws_internet_gateway.gw]
}

# 7. Public Route Table(公有區導航)
# 規則：要去全世界(0.0.0.0/0)，請走大門(IGW)
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = { Name = "wayne-public-rt" }
}

# 8. Private Route Table
# 規則：要去全世界(0.0.0.0/0)，請走NAT Gateway
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = { Name = "wayne-private-rt" }
}

# 9. 關聯(Assocation) - 把Subnet跟Route Table綁在一起
# 告訴Public Subnet 1&2 使用Public導航
resource "aws_route_table_association" "public_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2_assoc" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

# 告訴Private Subnet 1&2 使用Private導航
resource "aws_route_table_association" "private_1_assoc" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_2_assoc" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private_rt.id
}
