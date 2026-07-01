# This is the Packer configuration file for building GCE images which will be
# run by the Google OIM team in a Google internal GCP project. It binds sources
# to builds and provisioners.

variable "gcp_project" {
  default = "mlab-sandbox"
  description = "GCP project name"
  type = string
}

variable "version" {
  default = "latest"
  description = "The version string that will be appended to image names"
  type = string
}

variable "source_image" {
  default = "ubuntu-minimal-2404-noble-amd64-v20250818"
  description = "The source/base image for generate custom images"
  type = string
}

variable "api_key" {
  default = ""
  description = "The Autojoin API key used by the Google OIM team"
  type = string
}

variable "zone" {
  default = "us-central1-c"
  description = "GCE zone for the temporary Packer builder VM. Overridden per-attempt by the zone-fallback loop in setup_packer_google_oim_images.sh (see packer/zone_fallback.sh), which retries other zones on ZONE_RESOURCE_POOL_EXHAUSTED."
  type = string
}

source "googlecompute" "google-oim-instance" {
  disk_size        = 100
  image_name       = "google-oim-instance-${var.version}"
  project_id       = var.gcp_project
  source_image     = var.source_image
  ssh_username     = "packer"
  use_iap          = true
  use_internal_ip  = true
  zone             = var.zone
}

build {
  sources = [
    "source.googlecompute.google-oim-instance",
  ]

  provisioner "file" {
    sources = [
      "../configs/virtual_google_oim",
    ]
    destination = "/tmp"
  }

  # Builds were randomly failing because apt was unable to find packages that
  # should exist. I came across this documentation, which seems to be specific
  # to AWS, but appears to also work for GCE:
  # https://developer.hashicorp.com/packer/docs/debugging#issues-installing-ubuntu-packages
  provisioner "shell" {
    inline = [
      "cloud-init status --wait",
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "PROJECT=${var.gcp_project}",
      "API_KEY=${var.api_key}"
    ]
    script = "configure_oim_vm.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash {{ .Path }}"
  }
}
