# -*- mode: ruby -*-
# vi: set ft=ruby :

K8S_NODES = [
  { name: 'k8s-master', hostname: 'k8s-master', ip: '192.168.56.110' },
  { name: 'k8s-worker1', hostname: 'k8s-worker1', ip: '192.168.56.111' },
  { name: 'k8s-worker2', hostname: 'k8s-worker2', ip: '192.168.56.112' }
]

ANSIBLE_INVENTORY = {
  'master' => [K8S_NODES.first[:name]],
  'worker' => K8S_NODES.drop(1).map { |n| n[:name] }
}

Vagrant.configure("2") do |config|
  config.vm.box = "hashicorp-education/ubuntu-24-04"

  config.vm.provision "ansible" do |cfg|
    cfg.playbook = "playbooks/config.playbook.yml"
    cfg.groups = ANSIBLE_INVENTORY
  end

  config.vm.provision "ansible" do |cri|
    cri.playbook = "playbooks/cri.playbook.yml"
    cri.groups = ANSIBLE_INVENTORY
  end

  config.vm.provision "ansible" do |cluster|
    cluster.playbook = "playbooks/cluster.playbook.yml"
    cluster.groups = ANSIBLE_INVENTORY
    cluster.limit = "all"
  end

  config.vm.provision "shell", inline: <<-SHELL
    echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null
  SHELL

  K8S_NODES.each do |node|
    config.vm.define node[:name] do |node_vm|
      node_vm.vm.hostname = node[:hostname]
      node_vm.vm.network "private_network", ip: node[:ip]
      if node[:name] == 'k8s-master'
        node_vm.vm.provider :virtualbox do |vb|
          vb.memory = 2048
          vb.cpus = 2
        end
      else
        node_vm.vm.provider :virtualbox do |vb|
          vb.memory = 3072
          vb.cpus = 2
        end
      end
    end
  end
end
