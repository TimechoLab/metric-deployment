#!/bin/bash
apt-get update
if ! which prometheus > /dev/null 2>&1; then
  echo "安装prometheus"
  apt-get install -y prometheus
fi
if ! which prometheus > /dev/null 2>&1; then
  echo "prometheus未安装"
  exit
fi
if ! which grafana-server > /dev/null 2>&1; then
  echo "安装grafana"
  wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
  apt-get install -y apt-transport-https
  echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://mirrors.tuna.tsinghua.edu.cn/grafana/apt/ stable main" > /etc/apt/sources.list.d/grafana.list
  apt-get update
  apt-get install -y grafana
fi
if ! which grafana-server > /dev/null 2>&1; then
  echo "安装grafana"
  apt-get install -y adduser libfontconfig1
  wget https://dl.grafana.com/oss/release/grafana_9.4.7_amd64.deb
  dpkg -i grafana_9.4.7_amd64.deb
fi
if ! which grafana-server > /dev/null 2>&1; then
  echo "grafana未安装"
  exit
fi

if [ ! -n "$1" ]; then
    echo "configNodeIps参数不能为空"
    exit
fi
if [ ! -n "$2" ]; then
    echo "dataNodeIps不能为空"
    exit
fi

confignodeIpsStr=$1
datanodeIpsStr=$2
# 将,替换成:9091","
confignodeIpsList=$(echo ${confignodeIpsStr//,/:9091\",\"})
# 在前面插入["，在后面插入:9091"]
confignodeIpPortListStr="[\"${confignodeIpsList}:9091\"]"
# 将,替换成:9093","
datanodeIpsList=$(echo ${datanodeIpsStr//,/:9093\",\"})
# 在前面插入["，在后面插入:9093"]
datanodeIpPortListStr="[\"${datanodeIpsList}:9093\"]"
echo confignodeIpPortListStr
echo datanodeIpPortListStr

echo "修改prometheus配置文件"
PROMETHEUS_CONFIG_FILE="/etc/prometheus/prometheus.yml"

if ! cat $PROMETHEUS_CONFIG_FILE | grep confignode > /dev/null 2>&1; then
  echo "prometheus的IoTDB监控配置项不存在"
else
  echo "prometheus的IoTDB监控配置项已存在"
  sed -i '/\ \ - job_name: node/,$d' $PROMETHEUS_CONFIG_FILE
  sed -i '/\ \ - job_name: .\?confignode.\?/,$d' $PROMETHEUS_CONFIG_FILE
  sed -i '/\ \ - job_name: .\?datanode.\?/,$d' $PROMETHEUS_CONFIG_FILE
fi
echo "写入confignode target监控配置"
sed -i '$a\ \ - job_name: confignode' $PROMETHEUS_CONFIG_FILE
sed -i '$a\ \ \ \ static_configs:' $PROMETHEUS_CONFIG_FILE
sed -i '$a\ \ \ \ \ \ - targets: '"${confignodeIpPortListStr}"'' $PROMETHEUS_CONFIG_FILE
sed -i '$a\ \ \ \ honor_labels: true' $PROMETHEUS_CONFIG_FILE

echo "写入datanode target监控配置"
sed -i '$a\ \ -\ job_name: datanode' $PROMETHEUS_CONFIG_FILE
sed -i '$a\ \ \ \ static_configs:' $PROMETHEUS_CONFIG_FILE
sed -i '$a\ \ \ \ \ \ - targets: '"${datanodeIpPortListStr}"'' $PROMETHEUS_CONFIG_FILE
sed -i '$a\ \ \ \ honor_labels: true' $PROMETHEUS_CONFIG_FILE
systemctl restart prometheus
systemctl enable prometheus

GRAFANA_CONFIG_FILE="/etc/grafana/grafana.ini"
GRAFANA_PROVISIONING_DIR="/etc/grafana/provisioning"

echo "修改grafana-server配置文件"
if ! cat $GRAFANA_CONFIG_FILE | grep "^provisioning" > /dev/null 2>&1; then
  echo "grafana provisioning配置未修改"
  # 添加provisioning配置
  sed -i '$a"provisioning"='"${GRAFANA_PROVISIONING_DIR}"'' $GRAFANA_CONFIG_FILE
else
  echo "grafana provisioning配置已修改"
  # 修改未注释的provisioning
  sed -i 's#^provisioning.*$#provisioning='"${GRAFANA_PROVISIONING_DIR}"'#g' $GRAFANA_CONFIG_FILE
fi

echo "修改Grafana provisioning DataSource配置"
GRAFANA_DATA_SOURCE_CONFIG_FILE=${GRAFANA_PROVISIONING_DIR}/datasources/sample.yaml
if cat ${GRAFANA_DATA_SOURCE_CONFIG_FILE} | grep "^datasources:" > /dev/null 2>&1; then
  echo "Grafana datasources配置已存在"
  sed -i '/^datasources:/,$d' ${GRAFANA_DATA_SOURCE_CONFIG_FILE}
else
  echo "Grafana datasources配置不存在"
fi
sed -i '$adatasources:' ${GRAFANA_DATA_SOURCE_CONFIG_FILE}
sed -i '$a\ \ - name: DS_PROMETHEUS' ${GRAFANA_DATA_SOURCE_CONFIG_FILE}
sed -i '$a\ \ \ \ type: prometheus' ${GRAFANA_DATA_SOURCE_CONFIG_FILE}
sed -i '$a\ \ \ \ access: proxy' ${GRAFANA_DATA_SOURCE_CONFIG_FILE}
sed -i '$a\ \ \ \ url: http://localhost:9090' ${GRAFANA_DATA_SOURCE_CONFIG_FILE}

echo "修改Grafana provisioning Dashboard配置"
GRAFANA_DASHBOARDS_PATH=${GRAFANA_PROVISIONING_DIR}/dashboards/
GRAFANA_DASHBOARD_CONFIG_FILE=${GRAFANA_PROVISIONING_DIR}/dashboards/sample.yaml
if cat ${GRAFANA_DASHBOARD_CONFIG_FILE} | grep "^providers:" > /dev/null 2>&1; then
  echo "Grafana provisioning dashboard配置已存在"
  sed -i '/^providers:/,$d' ${GRAFANA_DASHBOARD_CONFIG_FILE}
else
  echo "Grafana provisioning dashboard配置不存在"
fi
sed -i '$aproviders:' ${GRAFANA_DASHBOARD_CONFIG_FILE}
sed -i '$a\ - name: \"default\"' ${GRAFANA_DASHBOARD_CONFIG_FILE}
sed -i '$a\ \ \ orgId: 1' ${GRAFANA_DASHBOARD_CONFIG_FILE}
sed -i '$a\ \ \ folder: \"\"' ${GRAFANA_DASHBOARD_CONFIG_FILE}
sed -i '$a\ \ \ folderUid: \"\"' ${GRAFANA_DASHBOARD_CONFIG_FILE}
sed -i '$a\ \ \ type: file' ${GRAFANA_DASHBOARD_CONFIG_FILE}
sed -i '$a\ \ \ options:' ${GRAFANA_DASHBOARD_CONFIG_FILE}
sed -i '$a\ \ \ \ \ path: \"'"${GRAFANA_DASHBOARDS_PATH}"'\"' ${GRAFANA_DASHBOARD_CONFIG_FILE}

echo "下载ConfigNodeDashboard"
CONFIG_NODE_DASHBOARD_FILE="ApacheIoTDBConfigNodeDashboard.json"
wget https://grafana.com/api/dashboards/17533/revisions/1/download -O ${CONFIG_NODE_DASHBOARD_FILE}
sed -i 's/\${DS_PROMETHEUS}/DS_PROMETHEUS/g' ${CONFIG_NODE_DASHBOARD_FILE}
mv ${CONFIG_NODE_DASHBOARD_FILE} ${GRAFANA_DASHBOARDS_PATH}

echo "下载DataNodeDashboard"
DATA_NODE_DASHBOARD_FILE="ApacheIoTDBDataNodeDashboard.json"
wget https://grafana.com/api/dashboards/17534/revisions/2/download -O ${DATA_NODE_DASHBOARD_FILE}
sed -i 's/\${DS_PROMETHEUS}/DS_PROMETHEUS/g' ${DATA_NODE_DASHBOARD_FILE}
mv ${DATA_NODE_DASHBOARD_FILE} ${GRAFANA_DASHBOARDS_PATH}

systemctl restart grafana-server
systemctl enable grafana-server