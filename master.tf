resource "scaleway_ip" "k8s_master_ip" {
  count = 1
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

  depends_on = ["data.external.scaleway_lb"]

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
#      "echo \"${local.lb_ip}  apiserver.${var.domain_name}\" >> /etc/hosts",
      "echo \"${element(scaleway_server.k8s_master.*.public_ip, count.index)} apiserver.${var.domain_name}\" >> /etc/hosts",
      "chmod +x /tmp/docker-install.sh && /tmp/docker-install.sh ${var.docker_version}",
      "chmod +x /tmp/kubeadm-install.sh && /tmp/kubeadm-install.sh ${var.k8s_version}",
      "kubeadm reset -f",
      // "kubeadm init --apiserver-advertise-address=${element(scaleway_server.k8s_master.*.private_ip, count.index)} --apiserver-cert-extra-sans=${element(scaleway_server.k8s_master.*.public_ip, count.index)},kube-apiserver.${var.domain_name} --kubernetes-version=${var.k8s_version} --ignore-preflight-errors=KubeletVersion",
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
