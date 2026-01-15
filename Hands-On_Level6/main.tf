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

# 10. ALB Security Group(允許外網連入)
resource "aws_security_group" "alb_sg" {
  name        = "wayne-alb-sg-custom"
  description = "Allow HTTP traffic to ALB."
  vpc_id      = aws_vpc.main.id # 重點：指定這個SG屬於新的VPC

  ingress {
    description = "HTTP from Internet."
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 11. EC2 Security Group(只允許ALB連入)
resource "aws_security_group" "ec2_sg" {
  name        = "wayne-ec2-sg-custom"
  description = "Allow traffic from ALB only."
  vpc_id      = aws_vpc.main.id # 指定新VPC

  ingress {
    description = "HTTP from ALB."
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    # 關鍵鎖定：不寫cidr_blocks，只信任ALB的識別證
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # EC2還是要上網下載Docker
  }
}

# 12. 建立ALB(住在Public Subnet)
resource "aws_lb" "wayne_alb" {
  name               = "wayne-alb-custom"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]

  # 關鍵：ALB要橫跨兩個
  subnets = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

resource "aws_lb_target_group" "wayne_tg" {
  name     = "wayne-tg-custom"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id # 指定新的VPC

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wayne_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wayne_tg.arn
  }
}

# 13. 建立模具(launch template)
# 這裡要引用AMI，我們需要把之前的Data Source補回來
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_launch_template" "wayne_lt" {
  name_prefix   = "wayne-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  # 綁定那個「只信任ALB」的嚴格SG
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  # User Data維持不變(安裝docker/nginx)
  user_data = filebase64("${path.module}/user-data.sh")

  tag_specifications {
    resource_type = "instance"
    tags = {
      "Name" = "Wayne-Private-Instance"
    }
  }
}

# 14. 建立ASG(住在Private Subnet)
resource "aws_autoscaling_group" "wayne_asg" {
  name                      = "wayne-asg-custom"
  desired_capacity          = 2
  max_size                  = 3
  min_size                  = 1
  target_group_arns         = [aws_lb_target_group.wayne_tg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.wayne_lt.id
    version = "$Latest"
  }

  # 關鍵：機器要藏在Private Subnet內
  vpc_zone_identifier = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

# 15. Output(告訴我大門在哪)
output "alb_dns_name" {
  value = aws_lb.wayne_alb.dns_name
}
