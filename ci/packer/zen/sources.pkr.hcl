# VirtualBox builds
source "virtualbox-iso" "centos-7" {
  vm_name = "${var.vm_name}"
  disk_size = "40000"
  guest_os_type = "RedHat_64"
  hard_drive_interface = "scsi"
  headless = "true"
  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--cpus", "4"],
    ["modifyvm", "{{.Name}}", "--memory", "12288"],
    ["modifyvm", "{{.Name}}", "--uartmode1", "disconnected"]
  ]
  iso_url = "http://centos.mirror.iweb.ca/7/isos/x86_64/CentOS-7-x86_64-Minimal-2003.iso"
  iso_checksum = "659691c28a0e672558b003d223f83938f254b39875ee7559d1a4a14c79173193"
  iso_checksum_type = "sha256"
  boot_command = [
    "<up><tab><spacebar>",
    "inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/centos7.ks.cfg<return>"
  ]
  http_directory = "files"
  ssh_username = "vagrant"
  ssh_password = "vagrant"
  ssh_timeout = "60m"
  shutdown_command = "sudo poweroff"
  # export
  format = "ova"
  output_directory = "${var.output_vbox_directory}"
}

# VMware builds
source "vmware-iso" "centos-7" {
  vm_name = "${var.vm_name}"
  disk_size = "40000"
  guest_os_type = "centos-64"
  disk_adapter_type = "scsi"
  headless = "true"
  vmx_data = {
    memsize = 12288
    numvcpus = 4
  } 
  iso_url = "http://centos.mirror.iweb.ca/7/isos/x86_64/CentOS-7-x86_64-Minimal-2003.iso"
  iso_checksum = "659691c28a0e672558b003d223f83938f254b39875ee7559d1a4a14c79173193"
  iso_checksum_type = "sha256"
  boot_command = [
    "<up><tab><spacebar>",
    "inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/centos7.ks.cfg<return>"
  ]
  http_directory = "files"
  ssh_username = "vagrant"
  ssh_password = "vagrant"
  ssh_timeout = "60m"
  shutdown_command = "sudo poweroff"
  # export
  format = "ova"
  output_directory = "${var.output_vmware_directory}"
}
