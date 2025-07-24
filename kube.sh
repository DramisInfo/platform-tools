scp ubuntu@192.168.20.10:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-dev1-config
sed -i 's/127.0.0.1/192.168.20.10/g' ~/.kube/k3s-dev1-config
sed -i 's/name: default$/name: k3s-dev1/g' ~/.kube/k3s-dev1-config
sed -i 's/cluster: default$/cluster: k3s-dev1/g' ~/.kube/k3s-dev1-config
sed -i 's/user: default$/user: k3s-dev1/g' ~/.kube/k3s-dev1-config
sed -i 's/current-context: default$/current-context: k3s-dev1/g' ~/.kube/k3s-dev1-config
cp ~/.kube/config ~/.kube/config.backup
KUBECONFIG=~/.kube/config:~/.kube/k3s-dev1-config kubectl config view --flatten > ~/.kube/config.tmp
mv ~/.kube/config.tmp ~/.kube/config

