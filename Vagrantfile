# -*- mode: ruby -*-
# vi: set ft=ruby :

K8S_NODES = [
  { name: 'k8s-master', hostname: 'k8s-master', ip: '192.168.56.110' },
  { name: 'k8s-worker1', hostname: 'k8s-worker1', ip: '192.168.56.111' },
  { name: 'k8s-worker2', hostname: 'k8s-worker2', ip: '192.168.56.112' },
]

  ANSIBLE_INVENTORY = {
  'master' => [K8S_NODES.first[:name]],
  'worker' => K8S_NODES.drop(1).map { |n| n[:name] },
  'kafka_brokers' => ['k8s-worker1', 'k8s-worker2']
}


Vagrant.configure("2") do |config|
  config.vm.box = "hashicorp-education/ubuntu-24-04"
 
  config.vm.provision "ansible" do |cfg|
    cfg.playbook = "playbooks/config.playbook.yml"
    cfg.groups = ANSIBLE_INVENTORY
  end


  config.vm.provision "ansible" do |cluster|
    cluster.playbook = "playbooks/cluster.playbook.yml"
    cluster.groups = ANSIBLE_INVENTORY
    cluster.limit = "all"
  end

  K8S_NODES.each do |node|
    config.vm.define node[:name] do |node_vm|
      node_vm.vm.hostname = node[:hostname]
     
      if node[:name] == 'k8s-master'
        node_vm.vm.network "private_network", ip: node[:ip]
        node_vm.vm.provider :virtualbox do |vb|
          vb.memory = 2048
          vb.cpus = 2
        end
      else
        node_vm.vm.network "private_network", ip: node[:ip]
        # node_vm.vm.network "forwarded_port", guest: 6379, host: 6379,auto_correct: true
        # node_vm.vm.network "forwarded_port", guest: 9092, host: 9092,auto_correct: true
        node_vm.vm.disk :disk, size: "30GB", primary: true
        node_vm.vm.provider :virtualbox do |vb|
          vb.memory = 4096
          vb.cpus = 4
        end
      end
    end
  end
end
