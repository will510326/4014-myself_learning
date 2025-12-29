# 1. 告訴 Terraform 我們要用 AWS
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# 2. 設定區域
provider "aws" {
  region = "ap-northeast-1" 
}

# 自動去找最新版的ubuntu
data "aws_ami" "ubuntu" {
  most_recent = true
  owners = ["099720109477"]

  filter {
    name = "name"
    values = [ "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" ]
  }
}


data "aws_vpc" "default_vpc" {
  default = true
}

data "aws_subnet" "default" {
  filter {
    name = "vpc-id"
    values = [ data.aws_vpc.default_vpc.id ]
  }
}


resource "aws_security_group" "my_sg" {
  name = "my-sg"
  vpc_id = data.aws_vpc.default_vpc.id

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Wayne-Security-Group"
  }
}

# create ALB security group
resource "aws_security_group" "alb_sg" {
  name = "wayne-alb-sg"
  description = "Allow HTTP traffic to ALB"
  vpc_id = data.aws_vpc.default_vpc.id

  ingress {
    description = "HTTP from Internet."
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
}

resource "aws_alb" "wayne_alb" {
  name = "wayne-web-alb"
  internal = false # 對外開放
  load_balancer_type = "application"
  security_groups = [ aws_security_group.alb_sg.id ]
  subnets = data.aws_ami.ubuntu.default.ids # Fetch subnets

  tags = {
    Name = "Wayne-ALB"
  }
}

# target group
resource "aws_lb_target_group" "wayne-tg" {
  name = "wayne-web-tg"
  port = 80
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default_vpc.id

  # Health Check
  # ALB will be ping this path to confirm EC2 status.
  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 30
    timeout = 5
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

# Listener - This responsible is transfer internal to target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_alb.wayne_alb.arn # 掛在哪一個ALB上
  port = 80
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wayne-tg.arn # 轉發給哪一個TG
  }
}

# 把你的EC2註冊到Target Group內
resource "aws_lb_target_group_attachment" "web_attachment" {
  target_group_arn = aws_lb_target_group.wayne-tg.arn
  target_id = aws_instance.web.id # 引用原本的EC2 ID
  port = 80
}

# key
resource "aws_key_pair" "waynelocalkey" {
  key_name = "wayne-key-iac"
  public_key = file("/home/wayne/.ssh/id_ed25519.pub")
}

resource "aws_instance" "web" {
  ami = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  # key
  key_name = aws_key_pair.waynelocalkey.key_name

  vpc_security_group_ids = [ aws_security_group.my_sg.id ]

  # execute script
  user_data = file("${path.module}/user-data.sh")

  user_data_replace_on_change = true

  tags = {
    Name = "Wayne-Iac-Server"
    Project = "SRE-Learning"
  }
}

#output
output "server_public_ip" {
  description = "Public IP address of the EC2 instance"
  value = aws_instance.web.public_ip
}

output "server_ssh_command" {
  description = "Command to SSH into the instance"
  value = "ssh -i /home/wayne/.ssh/id_ed25519 ubuntu@${aws_instance.web.public_ip}"
}

output "alb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.wayne_alb.dns_name
}