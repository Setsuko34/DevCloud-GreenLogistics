# Provisionne le cluster kind — équivalent Terraform de infra/kind-config.yaml.
# Non appliqué contre le cluster de démo en cours (cf. terraform/README.md) : géré
# manuellement via ./infra/up.sh pour ne pas risquer de le recréer avant la soutenance.

resource "kind_cluster" "this" {
  name           = var.cluster_name
  node_image     = var.node_image
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    networking {
      pod_subnet = "10.244.0.0/16"
    }

    node {
      role = "control-plane"

      extra_port_mappings {
        container_port = 80
        host_port       = 80
        protocol        = "TCP"
      }
      extra_port_mappings {
        container_port = 443
        host_port       = 443
        protocol        = "TCP"
      }
      extra_port_mappings {
        container_port = 30080
        host_port       = 30080
        protocol        = "TCP"
      }
      extra_port_mappings {
        container_port = 30090
        host_port       = 30090
        protocol        = "TCP"
      }
    }

    node {
      role = "worker"
    }
  }
}
