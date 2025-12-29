#!/bin/bash
sudo apt -y update
# 修正點：將 docker 改為 docker.io
sudo apt install -y docker.io 
sudo service docker start
sudo usermod -a -G docker ubuntu

# 架設docker nginx
docker run -d  -p 80:80 nginx:latest