#!/bin/bash

set -e

echo ".........----------------#### INSTALL STARTED ####----------------........."

# Improve terminal prompt
PS1='\[\e[01;36m\]\u\[\e[01;37m\]@\[\e[01;33m\]\H\[\e[01;37m\]:\[\e[01;32m\]\w\[\e[01;37m\]\$\[\033[0;37m\] '
echo "PS1='$PS1'" >> ~/.bashrc
sed -i '1s/^/force_color_prompt=yes\n/' ~/.bashrc
source ~/.bashrc

# Essential utilities
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release jq python3-pip jc vim build-essential

# Docker installation
apt-get install -y docker.io
systemctl enable docker
systemctl start docker

# Add docker group if missing
groupadd docker || true

# Kubernetes repo setup
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/kubernetes-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list

apt-get update

# Kubernetes install
KUBE_VERSION=1.20.0
apt-get install -y kubelet=${KUBE_VERSION}-00 kubeadm=${KUBE_VERSION}-00 kubectl=${KUBE_VERSION}-00 kubernetes-cni=0.8.7-00
apt-mark hold kubelet kubeadm kubectl

# Print VM UUID if available
if command -v dmidecode >/dev/null 2>&1; then
    echo "VM UUID:"
    sudo dmidecode | jc --dmidecode | jq .[1].values.uuid -r || echo "UUID not available"
fi

# Docker daemon config
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "storage-driver": "overlay2"
}
EOF

mkdir -p /etc/systemd/system/docker.service.d
systemctl daemon-reload
systemctl restart docker

# Enable kubelet
systemctl enable kubelet

echo ".........----------------#### INITIALIZING KUBERNETES ####----------------........."

# Clean up old config
rm -rf $HOME/.kube
kubeadm reset -f

# Init Kubernetes
kubeadm init --kubernetes-version=${KUBE_VERSION} \
  --pod-network-cidr=10.32.0.0/12 \
  --skip-token-print

mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Deploy weave network
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
sleep 60

# Untaint control plane node
kubectl taint nodes --all node-role.kubernetes.io/master- || true
kubectl taint nodes --all node.kubernetes.io/not-ready- || true

kubectl get nodes -o wide

echo ".........----------------#### INSTALLING JAVA + MAVEN ####----------------........."

apt install -y openjdk-11-jdk maven
java -version
mvn -v

echo ".........----------------#### INSTALLING JENKINS (WAR) ####----------------........."

mkdir -p /opt/jenkins
cd /opt/jenkins
wget https://get.jenkins.io/war-stable/2.426.1/jenkins.war

# Run Jenkins in background
nohup java -jar jenkins.war --httpPort=8080 &

echo "Jenkins started. Access it via: http://<your_vm_dns>:8080"
echo "Initial admin password:"
sleep 5
cat /root/.jenkins/secrets/initialAdminPassword 2>/dev/null || echo "Wait a few seconds then check /root/.jenkins/secrets/initialAdminPassword"

echo ".........----------------#### INSTALL COMPLETED ####----------------........."
