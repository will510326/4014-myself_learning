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