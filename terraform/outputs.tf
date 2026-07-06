output "cluster_name" {
  value = kind_cluster.this.name
}

output "kubeconfig_path" {
  value = kind_cluster.this.kubeconfig_path
}

output "namespaces" {
  value = { for k, v in module.namespace : k => v.name }
}
