# This is the main Packer configuration file. It binds sources to builds and
# provisioners. It will allow us, for example, to provision an AWS VM
# differently than we do a GCP VM, should that even be necessary.

variable "project_id" {
  default = "mlab-sandbox"
  description = "GCP project name"
  type = string
}

variable "image_version" {
  default = "latest"
  description = "The version string that will be appended to image names"
  type = string
}

source "googlecompute" "platform-cluster-node-gcp" {
  project_id   = var.project_id
  zone         = "us-central1-c"
  source_image = "ubuntu-minimal-2204-jammy-v20221122"
  image_name   = "platform-cluster-node-${var.image_version}"
  ssh_username = "packer"
  disk_size    = 100
}

source "googlecompute" "platform-cluster-api-gcp" {
  project_id   = var.project_id
  zone         = "us-central1-c"
  source_image = "ubuntu-minimal-2204-jammy-v20221122"
  image_name   = "platform-cluster-api-${var.image_version}"
  ssh_username = "packer"
  disk_size    = 100
}

# Provisioning common to all images.
build {
  sources = [
    "source.googlecompute.platform-cluster-node-gcp",
    "source.googlecompute.platform-cluster-api-gcp",
  ]

  provisioner "file" {
    sources = [
      "./virtual-files.tar.gz",
      "../config.sh"
    ]
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      "sudo tar -C / -xzf /tmp/virtual-files.tar.gz"
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "PROJECT=${var.project_id}"
    ]
    script = "configure_image_common.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash {{ .Path }}"
  }

  # Provision member node images.
  provisioner "shell" {
    only = ["googlecompute.platform-cluster-node-gcp"]
    environment_vars = [
      "PROJECT=${var.project_id}"
    ]
    script = "configure_node_image.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash {{ .Path }}"
  }

  # Provision API node images.
  provisioner "shell" {
    only = ["googlecompute.platform-cluster-api-gcp"]
    environment_vars = [
      "PROJECT=${var.project_id}"
    ]
    script = "configure_api_image.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash {{ .Path }}"
  }
}
