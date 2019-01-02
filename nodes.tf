resource "scaleway_ip" "k8s_node_ip" {
  count = "${var.nodes_count}"
}

resource "scaleway_server" "k8s_node" {
  count          = "${var.nodes_count}"
  name           = "${terraform.workspace}-node-${count.index + 1}"
  image          = "${data.scaleway_image.xenial.id}"
  type           = "${var.server_type_node}"
  public_ip      = "${element(scaleway_ip.k8s_node_ip.*.ip, count.index)}"
  #security_group = "${scaleway_security_group.node_security_group.id}"

  //  volume {
  //    size_in_gb = 50
  //    type       = "l_ssd"
  //  }

  depends_on = ["scaleway_server.k8s_master"]
}

resource "null_resource" "k8s_node_init" {
  count          = "${var.nodes_count}"

  connection {
    type        = "ssh"
    host        = "${element(scaleway_server.k8s_node.*.public_ip, count.index)}"
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
      "${data.external.kubeadm_join.result.command}",
      "sed -i '/.*${var.domain_name}/d' /etc/hosts", # load balancer will route requests to API server to the masters
    ]
  }
  provisioner "remote-exec" {
    inline = [
      "kubectl get pods --all-namespaces",
    ]

    on_failure = "continue"

    connection {
      type = "ssh"
      user = "root"
      host = "${scaleway_ip.k8s_master_ip.0.ip}"
    }
  }

}
