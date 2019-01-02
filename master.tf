resource "scaleway_ip" "k8s_master_ip" {
  count = "${var.masters_count}"
}

resource "scaleway_server" "k8s_master" {
  count          = 1
  name           = "${terraform.workspace}-master-${count.index + 1}"
  image          = "${data.scaleway_image.xenial.id}"
  type           = "${var.server_type}"
  public_ip      = "${element(scaleway_ip.k8s_master_ip.*.ip, count.index)}"
  #security_group = "${scaleway_security_group.master_security_group.id}"

  //  volume {
  //    size_in_gb = 50
  //    type       = "l_ssd"
  //  }
}

data "template_file" "kubeadm_config" {
  count = 1

  template = "${file("${path.module}/templates/kubeadm-config.yaml")}"

  vars {
    domain_name        = "${var.domain_name}"
    api_server_port    = "6443"
    kubernetes_version = "${var.k8s_version}"
    advertise_address  = "${element(scaleway_server.k8s_master.*.private_ip, count.index)}"
    public_ip          = "${element(scaleway_server.k8s_master.*.public_ip, count.index)}"
  }
}

resource "null_resource" "k8s_master_init" {
  count = 1

  connection {
    type        = "ssh"
    host        = "${element(scaleway_server.k8s_master.*.public_ip, count.index)}"
    user        = "root"
    private_key = "${file(var.private_key)}"
  }
  provisioner "file" {
    source      = "scripts/"
    destination = "/tmp"
  }
  provisioner "file" {
    source      = "addons/"
    destination = "/tmp"
  }
  provisioner "file" {
    content     = "${element(data.template_file.kubeadm_config.*.rendered, count.index)}"
    destination = "/tmp/kubeadm-config.yaml"
  }
  
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "echo \"${element(scaleway_server.k8s_master.*.public_ip, count.index)} apiserver.${var.domain_name}\" >> /etc/hosts",
      "chmod +x /tmp/docker-install.sh && /tmp/docker-install.sh ${var.docker_version}",
      "chmod +x /tmp/kubeadm-install.sh && /tmp/kubeadm-install.sh ${var.k8s_version}",
      "kubeadm reset -f",
      "kubeadm init --config=/tmp/kubeadm-config.yaml",
      "mkdir -p $HOME/.kube && cp /etc/kubernetes/admin.conf $HOME/.kube/config",
      "kubectl create secret -n kube-system generic weave-passwd --from-literal=weave-passwd=${var.weave_passwd}",
      "kubectl apply -f \"https://cloud.weave.works/k8s/net?password-secret=weave-passwd&k8s-version=$(kubectl version | base64 | tr -d '\n')\"",
      "chmod +x /tmp/monitoring-install.sh && /tmp/monitoring-install.sh ${var.arch}",
    ]
  }
  provisioner "local-exec" {
    command    = "./scripts/kubectl-conf.sh ${terraform.workspace} ${element(scaleway_server.k8s_master.*.public_ip, count.index)} ${element(scaleway_server.k8s_master.*.private_ip, count.index)} ${var.private_key}"
    on_failure = "continue"
  }

}

data "external" "kubeadm_join" {
  program = ["./scripts/kubeadm-token.sh"]

  query = {
    host = "${scaleway_ip.k8s_master_ip.0.ip}"
    key = "${var.private_key}"
  }

  depends_on = ["null_resource.k8s_master_init"]
}

resource "scaleway_server" "k8s_additional_master" {
  count          = "${var.masters_count - 1}"
  name           = "${terraform.workspace}-master-${count.index + 2}"
  image          = "${data.scaleway_image.xenial.id}"
  type           = "${var.server_type}"
  public_ip      = "${element(scaleway_ip.k8s_master_ip.*.ip, count.index + 1)}"
  #security_group = "${scaleway_security_group.master_security_group.id}"

  //  volume {
  //    size_in_gb = 50
  //    type       = "l_ssd"
  //  }

  depends_on = ["scaleway_server.k8s_master"]
}

resource "null_resource" "k8s_additional_master_init" {
  count         = "${var.masters_count - 1}"

  depends_on = ["null_resource.k8s_master_init", "scaleway_server.k8s_additional_master"]

  connection {
    type        = "ssh"
    host        = "${element(scaleway_ip.k8s_master_ip.*.ip, count.index + 1)}"
    user        = "root"
    private_key = "${file(var.private_key)}"
  }

  provisioner "file" {
    source      = "scripts/docker-install.sh"
    destination = "/tmp/docker-install.sh"
  }
  provisioner "file" {
    source      = "scripts/kubeadm-install.sh"
    destination = "/tmp/kubeadm-install.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "echo \"${element(scaleway_server.k8s_master.*.public_ip, 0)} apiserver.${var.domain_name}\" >> /etc/hosts", # while bootstrapping, do not rely on load balancer
      "chmod +x /tmp/docker-install.sh && /tmp/docker-install.sh ${var.docker_version}",
      "chmod +x /tmp/kubeadm-install.sh && /tmp/kubeadm-install.sh ${var.k8s_version}",
      "kubeadm reset -f",
   ]
  }

  # copy PKI and conf to reuse them in additional HA masters (https://kubernetes.io/docs/setup/independent/high-availability/)
  provisioner "local-exec" {
    command = <<CMD
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${var.private_key} root@${element(scaleway_ip.k8s_master_ip.*.ip, count.index + 1)} 'mkdir -p /etc/kubernetes/pki/etcd' && \
      scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${var.private_key} -3 root@${element(scaleway_ip.k8s_master_ip.*.ip, 0)}:/etc/kubernetes/admin.conf root@${element(scaleway_ip.k8s_master_ip.*.ip, count.index + 1)}:/etc/kubernetes/admin.conf && \
      PKI_FILES="ca.crt ca.key sa.key sa.pub front-proxy-ca.crt front-proxy-ca.key etcd/ca.crt etcd/ca.key"
      for file in $PKI_FILES; do
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${var.private_key} -3 root@${element(scaleway_ip.k8s_master_ip.*.ip, 0)}:/etc/kubernetes/pki/$file root@${element(scaleway_ip.k8s_master_ip.*.ip, count.index + 1)}:/etc/kubernetes/pki/$file
      done
CMD
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "${data.external.kubeadm_join.result.command} --experimental-control-plane",
      "sed -i '/.*${var.domain_name}/d' /etc/hosts", # load balancer will route requests to API server to the masters
   ]
  }
}

