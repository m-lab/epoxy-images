variable "project_id" {
  type = string
}

variable "image_version" {
  type = string
}

source "googlecompute" "mlab-platform-cluster-gcp" {
  project_id   = var.project_id
  zone         = "us-central1-c"
  source_image = "ubuntu-minimal-2204-jammy-v20221122"
  image_name   = "mlab-platform-cluster-${var.image_version}"
  ssh_username = "packer"
  disk_size    = 100
}

build {
  sources = ["sources.googlecompute.mlab-platform-cluster-gcp"]

  provisioner "file" {
    sources = [
      "./virtual-files.tar.gz",
      "../config.sh"
    ]
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/virtual-files.tar.gz /",
      "cd /",
      "sudo tar -xzf virtual-files.tar.gz"
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "PROJECT=${var.project_id}"
    ]
    script          = "configure_image.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash {{ .Path }}"
  }
}
