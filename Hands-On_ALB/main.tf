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

# 自動去找最新版的ubuntu
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}


data "aws_vpc" "default_vpc" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default_vpc.id]
  }
}


resource "aws_security_group" "my_sg" {
  name   = "my-sg"
  vpc_id = data.aws_vpc.default_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Wayne-Security-Group"
  }
}

# create ALB security group
resource "aws_security_group" "alb_sg" {
  name        = "wayne-alb-sg"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = data.aws_vpc.default_vpc.id

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

resource "aws_lb" "wayne_alb" {
  name               = "wayne-web-alb"
  internal           = false # 對外開放
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids # Fetch subnets

  tags = {
    Name = "Wayne-ALB"
  }
}

# target group
resource "aws_lb_target_group" "wayne-tg" {
  name     = "wayne-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default_vpc.id

  # Health Check
  # ALB will be ping this path to confirm EC2 status.
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Listener - This responsible is transfer internal to target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wayne_alb.arn # 掛在哪一個ALB上
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wayne-tg.arn # 轉發給哪一個TG
  }
}

# # 把你的EC2註冊到Target Group內
# resource "aws_lb_target_group_attachment" "web_attachment" {
#   target_group_arn = aws_lb_target_group.wayne-tg.arn
#   target_id        = aws_instance.web.id # 引用原本的EC2 ID
#   port             = 80
# }
# # for number 2
# resource "aws_lb_target_group_attachment" "web2_attachment" {
#   target_group_arn = aws_lb_target_group.wayne-tg.arn
#   target_id        = aws_instance.web2.id # 引用原本的EC2 ID
#   port             = 80
# }

# key
resource "aws_key_pair" "waynelocalkey" {
  key_name   = "wayne-key-iac"
  public_key = file("/home/wayne/.ssh/id_ed25519.pub")
}

# resource "aws_instance" "web" {
#   ami           = data.aws_ami.ubuntu.id
#   instance_type = var.instance_type

#   # key
#   key_name = aws_key_pair.waynelocalkey.key_name

#   vpc_security_group_ids = [aws_security_group.my_sg.id]

#   # execute script
#   user_data = file("${path.module}/user-data.sh")

#   user_data_replace_on_change = true

#   tags = {
#     Name    = "Wayne-Iac-Server"
#     Project = "SRE-Learning"
#   }
# }
# # AWS instence 2
# resource "aws_instance" "web2" {
#   ami           = data.aws_ami.ubuntu.id
#   instance_type = var.instance_type

#   # key
#   key_name = aws_key_pair.waynelocalkey.key_name

#   vpc_security_group_ids = [aws_security_group.my_sg.id]

#   # execute script
#   user_data = file("${path.module}/user-data.sh")

#   user_data_replace_on_change = true

#   tags = {
#     Name    = "Wayne-Iac-Server-2"
#     Project = "SRE-Learning"
#   }
# }

#output
# output "server_public_ip" {
#   description = "Public IP address of the EC2 instance"
#   value       = aws_instance.web.public_ip
# }

# output "server_ssh_command" {
#   description = "Command to SSH into the instance"
#   value       = "ssh -i /home/wayne/.ssh/id_ed25519 ubuntu@${aws_instance.web.public_ip}"
# }

output "alb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.wayne_alb.dns_name
}

resource "aws_launch_template" "wayne_lt" {
  name = "wayne-launch-template"

  # 1. 基礎硬體設定
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.waynelocalkey.key_name

  # 2. 網路設定(這裡只要設定SG，不用設subnet，subnet是給ASG決定的。)
  vpc_security_group_ids = [aws_security_group.my_sg.id]

  # 3. 識別證(userdata)
  # 注意：Launch Template規定要用filebase64編碼，跟之前file()不一樣！
  user_data = filebase64("${path.module}/user-data.sh")
  # 4. 標籤(給模組本身的標籤)
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "Wayne-ASG-Instance" # 後來出生的機器都是該名稱。
      Project = "SRE-Level-4"
    }
  }
}

# 建立「工廠產線」(Auto Scaling Group)
resource "aws_autoscaling_group" "wayne-asg" {
  name = "wayne-asg"
  # 1. 引用模具
  launch_template {
    id      = aws_launch_template.wayne_lt.id
    version = "$Latest" # 永遠用最新的模具
  }

  # 2. 決定位置(subnets)
  # 工廠要把機器生在哪裡？生在我們找到的那些subnets李
  vpc_zone_identifier = data.aws_subnets.default.ids

  # 3. 決定數量(SRE權力核心)
  desired_capacity = 2 # 期望值：我希望隨時都有2台
  min_size         = 1 # 最小值：最少不能低於1台
  max_size         = 3 # 最大值：最少不能低於3台

  # 4. 自動連結ALB(這還取代了之前的attachment)
  # 告訴ASG：「你生出來的機器，請自動幫我註冊道這個TG」
  target_group_arns = [aws_lb_target_group.wayne-tg.arn]

  # 5. 健康檢查機制
  # ELB = Elastic Load Balancer(即ALB)
  # 意思：如果ALB說這台機器壞了，ASG就會把它殺掉重開
  health_check_type         = "ELB"
  health_check_grace_period = 300 # 給新機器300的寬限期開機，不要一出生就檢查

  # 卻保有這行有加，避免destroy卡住
  force_delete = true
}
