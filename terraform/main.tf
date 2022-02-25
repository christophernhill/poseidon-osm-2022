#
# Create AWS instances for Jupyter lab and dask cluster
# Creates 
#   1 jupyter lab machine
#     - launches screen session looping to run jupyter lab
#   1 dask scheduler
#     - launches screen session looping to run dask-scheduler
#   n dask workers
#     - launches n workers looping in screen to run dask-worker with correct scheduler IP
#
#   all nodes are started in cluster placement group and have EFA and nitro networking.
#

# VPC 
#   - Find VPC and subnet to use based on VPC and subnet name tag parameters
#     this VPC should already have an internet gateway and a public subnet set to allow internet gateway ingress traffic from outside
#     to nodes with public IP (sshgw). There should alos be a private subnet should with a nat gateway route attached to allow outgoing traffic to the Internet
#     the nat gateway should be located on the subnet with the internet gateway
data "aws_vpc" "current-vpc" {
   filter {
     name = "tag:Name"
     values = ["${var.AWS_VPC_NAME}"]
   }
}
data "aws_subnet" "current-subnet" {
  filter {
    name   = "tag:Name"
    values = ["${var.AWS_SUBNET_NAME}"]
  }
}
data "aws_subnet" "current-priv-subnet" {
  filter {
    name   = "tag:Name"
    values = ["${var.AWS_PRIV_SUBNET_NAME}"]
  }
}
data "aws_internet_gateway" "current-gw" {
  filter {
   name   = "attachment.vpc-id"
   values = ["${data.aws_vpc.current-vpc.id}"]
  }
}
data "aws_ami" "current-jlab-ami" {
  owners = ["self"]
  filter {
    name   = "name"
    values = ["${var.AWS_JLAB_AMI}"]
  }
}
data "aws_ec2_instance_type" "current-jlab-itype" {
  instance_type = "${var.AWS_JLAB_ITYPE}"
}
data "aws_ec2_instance_type" "current-dsched-itype" {
  instance_type = "${var.AWS_DSCHED_ITYPE}"
}
data "aws_ec2_instance_type" "current-sshgw-itype" {
  instance_type = "${var.AWS_SSHGW_ITYPE}"
}

# Get the key to use
data "aws_key_pair" "current-key-pair" {
  key_name = "${var.AWS_SSH_KEY_NAME}"
}

# Need to create PG
resource "aws_placement_group" "current-pg" {
  name = "${var.AWS_PG_NAME}"
  strategy = "cluster"
}

# Create the jupyter-lab instance 
#  in placement group, with EFA network, AWS_JLAB_ITYPE instance type and AWS_OSM2002_AMI AMI
#  o create network interface
resource "aws_network_interface" "current-jlab-nic" {
  interface_type  = "efa"
  subnet_id       = data.aws_subnet.current-priv-subnet.id
  security_groups = ["${resource.aws_security_group.ssh-allowed.id}",
                     "${resource.aws_security_group.internal-allowed.id}"
                    ]
  private_ip_list = [cidrhost("${data.aws_subnet.current-priv-subnet.cidr_block}",10)]
  private_ip_list_enabled = true
  ### attachment {
  ###  instance = aws_instance.current-jlab-instance.id
  ###  device_index = 1
  ### }
}

resource "aws_network_interface" "current-dsched-nic" {
  interface_type  = "efa"
  subnet_id       = data.aws_subnet.current-priv-subnet.id
  security_groups = ["${resource.aws_security_group.ssh-allowed.id}",
                     "${resource.aws_security_group.internal-allowed.id}"
                    ]
  private_ip_list = [cidrhost("${data.aws_subnet.current-priv-subnet.cidr_block}",11)]
  private_ip_list_enabled = true
}

resource "aws_network_interface" "current-dworker-nics" {
  count           = var.AWS_DWORKERS_COUNT
  interface_type  = "efa"
  subnet_id       = data.aws_subnet.current-priv-subnet.id
  security_groups = ["${resource.aws_security_group.ssh-allowed.id}",
                     "${resource.aws_security_group.internal-allowed.id}"
                    ]
  private_ip_list = [cidrhost("${data.aws_subnet.current-priv-subnet.cidr_block}",11+count.index+1)]
  private_ip_list_enabled = true
}

###    count  = length(local.servers_list)
###    vpc_id = "${data.aws_vpc.current-vpc.id}"
###    cidr_block = cidrsubnet(data.aws_vpc.current-vpc.cidr_block,10,count.index+1)

#  o create security groups
#  1. publicly accessible instances allow ssh
resource "aws_security_group" "ssh-allowed" {

    vpc_id = "${data.aws_vpc.current-vpc.id}"

    egress {
        from_port = 0
        to_port = 0
        protocol = -1
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

}
resource "aws_security_group" "internal-allowed" {

    vpc_id = "${data.aws_vpc.current-vpc.id}"

    egress {
        from_port = 0
        to_port = 0
        protocol = -1
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 0
        to_port = 0
        protocol = -1
        cidr_blocks = ["${data.aws_vpc.current-vpc.cidr_block}"]
    }

}

#  o create sshgw instance
resource "aws_instance" "current-sshgw-instance" {
  ami = data.aws_ami.current-jlab-ami.id
  instance_type = data.aws_ec2_instance_type.current-sshgw-itype.id
  placement_group = resource.aws_placement_group.current-pg.id

  # the Public SSH key
  key_name = "${data.aws_key_pair.current-key-pair.key_name}"
  
  associate_public_ip_address = true

  subnet_id       = data.aws_subnet.current-subnet.id
  security_groups = ["${resource.aws_security_group.ssh-allowed.id}",
                     "${resource.aws_security_group.internal-allowed.id}"
                    ]
    user_data = <<EOT
#cloud-config
package_update: true
package_upgrade: true

packages:
    - fail2ban

write_files:
    - content: |
        [sshd]
        enabled = true
        mode    = aggressive

      path: /etc/fail2ban/jail.d/defaults-debian.conf
      permissions: '0644'
EOT
}

#  o create jupyter-lab instance
resource "aws_instance" "current-jlab-instance" {
  ami = data.aws_ami.current-jlab-ami.id
  instance_type = data.aws_ec2_instance_type.current-jlab-itype.id
  placement_group = resource.aws_placement_group.current-pg.id

  # the Public SSH key
  key_name = "${data.aws_key_pair.current-key-pair.key_name}"

  network_interface {
    device_index = 0
    network_interface_id = resource.aws_network_interface.current-jlab-nic.id
  }
    user_data = <<EOT
#cloud-config
package_update: true
package_upgrade: true

packages:
    - fail2ban

write_files:
    - content: |
        [sshd]
        enabled = true
        mode    = aggressive

      path: /etc/fail2ban/jail.d/defaults-debian.conf
      permissions: '0644'
    - content: |
        #!/bin/bash
        screen -L -Logfile jupyter-lab-console-log.txt -d -m -S "jupyter-lab-console" /bin/bash -c "while [ 1 ]; do sleep 1 ; jupyter-lab --no-browser --ServerApp.token='' --ServerApp.password='' ; done"
      path: /home/ubuntu/start-jlab.sh
      permissions: '0755'
    - content: |
       # service name:     jupyter-lab.service 
       # path:             /lib/systemd/system/jupyter-lab.service

       [Unit]
       Description=Jupyter Lab Server

       [Service]
       Type=simple
       PIDFile=/run/jupyter-lab.pid

       EnvironmentFile=/home/ubuntu/.jupyter/env

       # Jupyter Notebook: change PATHs as needed for your system
       ExecStart=/home/ubuntu/miniconda3/envs/projects-osn/bin/jupyter-lab --no-browser --ServerApp.token='' --ServerApp.password='' --ServerApp.ip='*'

       User=ubuntu
       Group=ubuntu
       WorkingDirectory=/home/ubuntu
       Restart=always
       RestartSec=10

       [Install]
       WantedBy=multi-user.target
      path: /lib/systemd/system/jupyter-lab.service
      permissions: '0755'
    - content: |
        #!/bin/bash
        su -l ubuntu /bin/bash -c ". /home/ubuntu/miniconda3/bin/activate projects-osn; /home/ubuntu/miniconda3/envs/projects-osn/bin/python -m pip install --user xarray==0.21.1"
        su -l ubuntu /bin/bash -c ". /home/ubuntu/miniconda3/bin/activate projects-osn; /home/ubuntu/miniconda3/envs/projects-osn/bin/python -m pip install --user zarr==2.11.0"
        su -l ubuntu /bin/bash -c ". /home/ubuntu/miniconda3/bin/activate projects-osn; env" | grep -e '^CONDA_EXE' -e '^CONDA_PREFIX' -e '^CONDA_PROMPT_MODIFIER' -e '^PROJ_LIB' -e '^CONDA_PYTHON_EXE' -e '^CONDA_DEFAULT_ENV' -e '^PATH' > /home/ubuntu/.jupyter/env
        systemctl --no-block restart jupyter-lab
      path: /home/ubuntu/set-jlab-env.sh
      permissions: '0755'
runcmd:        
    - [ su, -l, ubuntu, /bin/bash, -c, "mkdir -p /home/ubuntu/.jupyter" ]
    - [ su, -l, ubuntu, /bin/bash, -c, "touch /home/ubuntu/.jupyter/env; chmod 755 /home/ubuntu/.jupyter/env" ]
    - [ /home/ubuntu/set-jlab-env.sh ]
    - [ systemctl, --no-block, restart, jupyter-lab]
EOT
}

#  o create dask scheduler instance
resource "aws_instance" "current-dsched-instance" {
  #  create 1 of these if there is at least one worker
  ami = data.aws_ami.current-jlab-ami.id
  instance_type = data.aws_ec2_instance_type.current-dsched-itype.id
  placement_group = resource.aws_placement_group.current-pg.id

  # the Public SSH key
  key_name = "${data.aws_key_pair.current-key-pair.key_name}"

  network_interface {
    device_index = 0
    network_interface_id = resource.aws_network_interface.current-dsched-nic.id
  }
    user_data = <<EOT
#cloud-config
package_update: true
package_upgrade: true

packages:
    - fail2ban

write_files:
    - content: |
        [sshd]
        enabled = true
        mode    = aggressive

      path: /etc/fail2ban/jail.d/defaults-debian.conf
      permissions: '0644'
    - content: |
       # service name:     dask-scheduler.service 
       # path:             /lib/systemd/system/dask-scheduler.service

       [Unit]
       Description=Dask Scheduler

       [Service]
       Type=simple
       PIDFile=/run/dask-scheduler.pid

       EnvironmentFile=/home/ubuntu/.jupyter/env

       # Jupyter Notebook: change PATHs as needed for your system
       ExecStart=/home/ubuntu/miniconda3/envs/projects-osn/bin/dask-scheduler

       User=ubuntu
       Group=ubuntu
       WorkingDirectory=/home/ubuntu
       Restart=always
       RestartSec=10

       [Install]
       WantedBy=multi-user.target
      path: /lib/systemd/system/dask-scheduler.service
      permissions: '0755'
    - content: |
        #!/bin/bash
        su -l ubuntu /bin/bash -c ". /home/ubuntu/miniconda3/bin/activate projects-osn; /home/ubuntu/miniconda3/envs/projects-osn/bin/python -m pip install --user xarray==0.21.1"
        su -l ubuntu /bin/bash -c ". /home/ubuntu/miniconda3/bin/activate projects-osn; /home/ubuntu/miniconda3/envs/projects-osn/bin/python -m pip install --user zarr==2.11.0"
        su -l ubuntu /bin/bash -c ". /home/ubuntu/miniconda3/bin/activate projects-osn; env" | grep -e '^CONDA_EXE' -e '^CONDA_PREFIX' -e '^CONDA_PROMPT_MODIFIER' -e '^PROJ_LIB' -e '^CONDA_PYTHON_EXE' -e '^CONDA_DEFAULT_ENV' -e '^PATH' > /home/ubuntu/.jupyter/env
        systemctl --no-block restart dask-scheduler
      path: /home/ubuntu/set-jlab-env.sh
      permissions: '0755'
runcmd:        
    - [ su, -l, ubuntu, /bin/bash, -c, "mkdir -p /home/ubuntu/.jupyter" ]
    - [ su, -l, ubuntu, /bin/bash, -c, "touch /home/ubuntu/.jupyter/env; chmod 755 /home/ubuntu/.jupyter/env" ]
    - [ /home/ubuntu/set-jlab-env.sh ]
    - [ systemctl, --no-block, restart, dask-scheduler]
EOT
}

#  o create dask worker instances
resource "aws_instance" "current-dwork-instances" {
  count           = var.AWS_DWORKERS_COUNT
  ami = data.aws_ami.current-jlab-ami.id
  instance_type = data.aws_ec2_instance_type.current-jlab-itype.id
  placement_group = resource.aws_placement_group.current-pg.id

  # the Public SSH key
  key_name = "${data.aws_key_pair.current-key-pair.key_name}"

  network_interface {
    device_index = 0
    network_interface_id = resource.aws_network_interface.current-dworker-nics[count.index].id
  }

    user_data = <<EOT
#cloud-config
package_update: true
package_upgrade: true

packages:
    - fail2ban

write_files:
    - content: |
        [sshd]
        enabled = true
        mode    = aggressive

      path: /etc/fail2ban/jail.d/defaults-debian.conf
      permissions: '0644'
    - content: |
       # service name:     dask-worker.service 
       # path:             /lib/systemd/system/dask-worker.service

       [Unit]
       Description=Dask Worker

       [Service]
       Type=simple
       PIDFile=/run/dask-worker.pid

       EnvironmentFile=/home/ubuntu/.jupyter/env

       # Jupyter Notebook: change PATHs as needed for your system
       ExecStart=/home/ubuntu/miniconda3/envs/projects-osn/bin/dask-worker 10.0.1.11:8786

       User=ubuntu
       Group=ubuntu
       WorkingDirectory=/home/ubuntu
       Restart=always
       RestartSec=10

       [Install]
       WantedBy=multi-user.target
      path: /lib/systemd/system/dask-worker.service
      permissions: '0755'
    - content: |
        #!/bin/bash
        su -l ubuntu /bin/bash -c ". /home/ubuntu/miniconda3/bin/activate projects-osn; /home/ubuntu/miniconda3/envs/projects-osn/bin/python -m pip install --user xarray==0.21.1"
        su -l ubuntu /bin/bash -c ". /home/ubuntu/miniconda3/bin/activate projects-osn; /home/ubuntu/miniconda3/envs/projects-osn/bin/python -m pip install --user zarr==2.11.0"
        su -l ubuntu /bin/bash -c ". /home/ubuntu/miniconda3/bin/activate projects-osn; env" | grep -e '^CONDA_EXE' -e '^CONDA_PREFIX' -e '^CONDA_PROMPT_MODIFIER' -e '^PROJ_LIB' -e '^CONDA_PYTHON_EXE' -e '^CONDA_DEFAULT_ENV' -e '^PATH' > /home/ubuntu/.jupyter/env
        systemctl --no-block restart dask-worker
      path: /home/ubuntu/set-jlab-env.sh
      permissions: '0755'
runcmd:        
    - [ su, -l, ubuntu, /bin/bash, -c, "mkdir -p /home/ubuntu/.jupyter" ]
    - [ su, -l, ubuntu, /bin/bash, -c, "touch /home/ubuntu/.jupyter/env; chmod 755 /home/ubuntu/.jupyter/env" ]
    - [ /home/ubuntu/set-jlab-env.sh ]
    - [ systemctl, --no-block, restart, dask-worker]
EOT
}

output "ipj-list" {
       value=resource.aws_instance.current-jlab-instance.private_ip
       description="jlab ip ="
}
output "ipds-list" {
       value=resource.aws_instance.current-dsched-instance.private_ip
       description="ds ip ="
}
output "sshgwip" {
       value=resource.aws_instance.current-sshgw-instance.public_ip
       description="sshgw ip ="
}

# Start jupyter with
# jupyter-lab --no-browser --ServerApp.token='' --ServerApp.password=''
# -or as a perpetual restart-
# while [ 1 ]; do sleep 1 ; jupyter-lab --no-browser --ServerApp.token='' --ServerApp.password='' ; done
# -or from startup script-
# screen -L -Logfile jupyter-lab-console-log.txt -d -m -S "jupyter-lab-console" /bin/bash -c "while [ 1 ]; do sleep 1 ; jupyter-lab --no-browser --ServerApp.token='' --ServerApp.password='' ; done"
#
# to get env 
# su -l ubuntu /bin/bash -c "touch /home/ubuntu/.jupyter/env; chmod 755 /home/ubuntu/.jupyter/env"
# su -l ubuntu /bin/bash -c ". /home/ubuntu/miniconda3/bin/activate projects-osn; env" | grep -e '^CONDA_EXE' -e '^CONDA_PREFIX' -e '^CONDA_PROMPT_MODIFIER' -e '^PROJ_LIB' -e '^CONDA_PYTHON_EXE' -e '^CONDA_DEFAULT_ENV' -e '^PATH' > /home/ubuntu/.jupyter/env
