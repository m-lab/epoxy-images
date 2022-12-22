# This is the main Packer configuration file. It binds sources to builds and
# provisioners. It will allow us, for example, to provision an AWS VM
# differently than we do a GCP VM, should that even be necessary.

variable "gcp_project" {
  default = "mlab-sandbox"
  description = "GCP project name"
  type = string
}

variable "image_version" {
  default = "latest"
  description = "The version string that will be appended to image names"
  type = string
}

source "googlecompute" "platform-cluster-instance" {
  project_id   = var.gcp_project
  zone         = "us-central1-c"
  source_image = "ubuntu-minimal-2204-jammy-v20221122"
  image_name   = "platform-cluster-instance-${var.image_version}"
  ssh_username = "packer"
  disk_size    = 100
}

source "googlecompute" "platform-cluster-api-instance" {
  project_id   = var.gcp_project
  zone         = "us-central1-c"
  source_image = "ubuntu-minimal-2204-jammy-v20221122"
  image_name   = "platform-cluster-api-instance-${var.image_version}"
  ssh_username = "packer"
  disk_size    = 100
}

build {
  sources = [
    "source.googlecompute.platform-cluster-instance",
    "source.googlecompute.platform-cluster-api-instance",
  ]

  # This provisioning step gets run for all sources.
  provisioner "file" {
    sources = [
      "./virtual-files.tar.gz",
      "../config.sh"
    ]
    destination = "/tmp/"
  }

  # This provisioning step gets run for all sources.
  provisioner "shell" {
    inline = [
      "sudo tar -C / -xzf /tmp/virtual-files.tar.gz"
    ]
  }

  # This provisioning step gets run for all sources.
  provisioner "shell" {
    environment_vars = [
      "PROJECT=${var.gcp_project}"
    ]
    script = "configure_image_common.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash {{ .Path }}"
  }

  # This provisioning block only gets run for the "platform-cluster-instance"
  # source.
  provisioner "shell" {
    only = ["googlecompute.platform-cluster-instance"]
    environment_vars = [
      "PROJECT=${var.gcp_project}"
    ]
    script = "configure_image.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash {{ .Path }}"
  }

  # This provisioning block only gets run for the
  # "platform-cluster-api-instance" source.
  provisioner "shell" {
    only = ["googlecompute.platform-cluster-api-instance"]
    environment_vars = [
      "PROJECT=${var.gcp_project}"
    ]
    script = "configure_api_image.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash {{ .Path }}"
  }
}
