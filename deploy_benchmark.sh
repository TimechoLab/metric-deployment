#!/bin/bash
apt update
if ! which prometheus > /dev/null 2>&1; then
  apt install -y openjdk-8-jdk
fi
if ! which unzip > /dev/null 2>&1; then
  apt install -y unzip
fi
runningServer=$(ps -ef | grep workbench-1.0.0.jar | grep -v grep | awk '{print$2}')
if [ -n "${runningServer}" ]; then
  kill "$runningServer"
fi
if [ ! -d Timecho-workbench-1.0.1.2 ]; then
  wget https://timecho-pub.oss-cn-beijing.aliyuncs.com/Timecho-Workbench-1.0.1.2.zip -O Timecho-Workbench.zip
  unzip Timecho-Workbench.zip
fi
source cd ./Timecho-workbench-1.0.1.2
nohup java -jar ./workbench-1.0.0.jar --server.port=8080 &
