locals {
  nodes_ips = "${concat(scaleway_server.k8s_master.*.public_ip, scaleway_server.k8s_node.*.public_ip)}"
  masters_private_ips = "${scaleway_server.k8s_master.*.private_ip}"
}

resource "null_resource" "scaleway_lb" {
  provisioner "local-exec" {
    command    = "${path.module}/scripts/scaleway-lb.sh"

    environment {
      SCALEWAY_LB_NAME             = "${var.lb_name}"
      DELETE_EXISTING              = "false"
      KUBE_API_SERVER_FORWARD_PORT = 6443
      KUBE_API_SERVER_PORT         = 6443
      MASTER_NODES_IPS             = "\"${join("\",\"", local.masters_private_ips)}\""
    }

    on_failure = "continue"
  }
}

data "external" "scaleway_lb" {
  program = ["${path.module}/scripts/scaleway-lb-ip.sh"]

  query = {
    lb_name = "${var.lb_name}"
  }

  depends_on = ["null_resource.scaleway_lb"]
}

output "scaleway_lb_ip" {
  value = "${data.external.scaleway_lb.result["scaleway_lb_ip"]}"
}

data "template_file" "traefik" {
  template = "${file("${path.module}/addons/traefik.yaml")}"

  vars {
    replicas_count  = "${length(local.nodes_ips)}"
    domain_name     = "${var.domain_name}"
    externalIPs     = "${join("\n    - ", local.nodes_ips)}"
    traefik_version = "${var.traefik_version}"
  }
}

resource "null_resource" "traefik_init" {
  depends_on = ["null_resource.k8s_master_init"]

  connection {
    type        = "ssh"
    host        = "${scaleway_server.k8s_master.0.public_ip}"
    user        = "root"
    private_key = "${file(var.private_key)}"
  }

  provisioner "file" {
    content     = "${data.template_file.traefik.rendered}"
    destination = "/tmp/traefik.yaml"
  }
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "kubectl apply -f /tmp/traefik.yaml"
    ]
  }
}

