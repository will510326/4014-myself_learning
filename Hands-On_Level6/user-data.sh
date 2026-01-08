#!/bin/bash
sudo apt -y update
sudo apt install -y docker.io
sudo service docker start
sudo usermod -a -G docker ubuntu

# 取得這台機器的 Hostname (例如 ip-172-31-xx-xx)
MY_IP=$(hostname -f)

# 啟動 Nginx，並透過 sed 指令把首頁內容改掉，塞入這台機器的名字
# 這樣我們重新整理網頁時，就知道是誰在服務我們
docker run -d -p 80:80 nginx:latest
sleep 10 # 等容器跑起來
docker exec $(docker ps -q) sh -c "echo '<h1>Hello from Server: $MY_IP</h1>' > /usr/share/nginx/html/index.html"