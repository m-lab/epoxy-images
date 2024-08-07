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

variable "source_image" {
  default = "ubuntu-minimal-2204-jammy-v20221122"
  description = "The source/base image for generate custom images"
  type = string
}

source "googlecompute" "platform-cluster-instance" {
  disk_size        = 100
  image_name       = "platform-cluster-instance-${var.image_version}"
  project_id       = var.gcp_project
  source_image     = var.source_image
  ssh_username     = "packer"
  use_iap          = true
  use_internal_ip  = true
  zone             = "us-central1-c"
}

source "googlecompute" "platform-cluster-internal-instance" {
  disk_size        = 100
  image_name       = "platform-cluster-internal-instance-${var.image_version}"
  project_id       = var.gcp_project
  source_image     = var.source_image
  ssh_username     = "packer"
  use_iap          = true
  use_internal_ip  = true
  zone             = "us-central1-c"
}

source "googlecompute" "platform-cluster-api-instance" {
  disk_size        = 100
  image_name       = "platform-cluster-api-instance-${var.image_version}"
  project_id       = var.gcp_project
  source_image     = var.source_image
  ssh_username     = "packer"
  use_iap          = true
  use_internal_ip  = true
  zone             = "us-central1-c"
}

build {
  sources = [
    "source.googlecompute.platform-cluster-instance",
    "source.googlecompute.platform-cluster-internal-instance",
    "source.googlecompute.platform-cluster-api-instance",
  ]

  #
  # The following provisioning step gets run for all sources.
  #

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

  # Builds were randomly failing because apt was unable to find packages that
  # should exist. I came across this documentation, which seems to be specific
  # to AWS, but appears to also work for GCE:
  # https://developer.hashicorp.com/packer/docs/debugging#issues-installing-ubuntu-packages
  provisioner "shell" {
    inline = [
      "cloud-init status --wait"
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "PROJECT=${var.gcp_project}"
    ]
    script = "configure_image_common.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash {{ .Path }}"
  }

  #
  # This provisioning block only gets run for the "platform-cluster-instance"
  # source.
  #
  provisioner "shell" {
    only = ["googlecompute.platform-cluster-instance"]
    environment_vars = [
      "PROJECT=${var.gcp_project}"
    ]
    script = "configure_image.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash {{ .Path }}"
  }

  #
  # This provisioning block only gets run for the
  # "platform-cluster-internal-instance" source.
  #
  provisioner "shell" {
    only = ["googlecompute.platform-cluster-internal-instance"]
    environment_vars = [
      "PROJECT=${var.gcp_project}"
    ]
    script = "configure_image_internal.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash {{ .Path }}"
  }

  #
  # This provisioning block only gets run for the
  # "platform-cluster-api-instance" source.
  #
  provisioner "shell" {
    only = ["googlecompute.platform-cluster-api-instance"]
    environment_vars = [
      "PROJECT=${var.gcp_project}"
    ]
    script = "configure_image_api.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash {{ .Path }}"
  }
}
