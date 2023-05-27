#############################################
  #vpc
#############################################
module "vpc1" {
  source  = "terraform-aws-modules/vpc/aws"
  name = "web-vpc"
  cidr = var.web_vpc_cidr

  azs             = var.vpc_azs
  public_subnets  = var.web_vpc_public_subnets
  private_subnets = var.web_vpc_private_subnets

  public_subnet_tags = {
    Name = "web-public-subnet"
  }

  private_subnet_tags = {
    Name = "web-private-subnet"
  }

  enable_nat_gateway = true
  single_nat_gateway = false
  one_nat_gateway_per_az = true
  map_public_ip_on_launch = true

  tags = {
    Name= "web-vpc"
    Terraform = "true"
    Environment = "stage"
    Facing= "public"
  }
}

module "vpc2" {
  source  = "terraform-aws-modules/vpc/aws"
  name = "db-vpc"
  cidr = var.db_vpc_cidr

  azs             = var.vpc_azs
  public_subnets  = var.db_vpc_public_subnets
  private_subnets  = var.db_vpc_private_subnets

  public_subnet_tags = {
    Name = "db-public-subnet"
  }

  private_subnet_tags = {
    Name = "db-private-subnet"
  }

  enable_nat_gateway = true
  single_nat_gateway = false
  one_nat_gateway_per_az = true
  map_public_ip_on_launch = true

  tags = {
    Name= "db-vpc"
    Terraform = "true"
    Environment = "stage"
    Facing= "private"
  }
}

#############################################
  #vpc_peering
#############################################

resource "aws_vpc_peering_connection" "vpc_peering" {
  peer_vpc_id   = module.vpc2.vpc_id
  vpc_id        = module.vpc1.vpc_id

  auto_accept = true

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  tags = {
    Name = "vpc-peering"
  }
}

#############################################
  #vpc_route
#############################################

resource "aws_route" "vpc1_to_vpc2" {
  route_table_id            = "${module.vpc1.public_route_table_ids[0]}"
  destination_cidr_block    = "${module.vpc2.vpc_cidr_block}"
  vpc_peering_connection_id = "${aws_vpc_peering_connection.vpc_peering.id}"
}

resource "aws_route" "vpc2_to_vpc1" {
  route_table_id            = "${module.vpc2.public_route_table_ids[0]}"
  destination_cidr_block    = "${module.vpc1.vpc_cidr_block}"
  vpc_peering_connection_id = "${aws_vpc_peering_connection.vpc_peering.id}"
}

#############################################
  #eks
#############################################

module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_name                  = "task-eks-cluster"
  cluster_version               = "1.24"
  vpc_id                        = module.vpc1.vpc_id
  subnet_ids                    = module.vpc1.public_subnets
  cluster_endpoint_public_access = true
  cluster_endpoint_private_access = true
  eks_managed_node_groups = {
    one = {
      name           = "node-group-1"
      instance_types = ["t3.small"]
      min_size       = 1
      max_size       = 3
      desired_size   = 1
    }
    two = {
      name           = "node-group-2"
      instance_types = ["t3.small"]
      min_size       = 1
      max_size       = 3
      desired_size   = 1
    }
  }
}

resource "null_resource" "install_helm" {
  depends_on = [module.eks]

  provisioner "local-exec" {
    command = <<-EOT
      curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > get_helm.sh
      chmod +x get_helm.sh
      ./get_helm.sh
    EOT
  }
}



#############################################
  #kube_ctl
#############################################

resource "null_resource" "install_kubectl" {
  provisioner "local-exec" {
    command = "curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x ./kubectl && sudo mv ./kubectl /usr/local/bin/kubectl && aws eks --region ap-south-1 update-kubeconfig --name task-eks-cluster"
  }
  depends_on = [
    module.eks
  ]
}

#############################################
  #key_pairs
#############################################

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "mongo_key" {
  key_name   = "mongo_key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

resource "local_file" "private_key" {
  filename = "private_key.pem"
  content  = tls_private_key.ssh_key.private_key_pem
  file_permission = "0600"
}

#############################################
  #mongo_instance
#############################################

resource "aws_instance" "mongo" {
  count = 3

  ami           = var.ami
  instance_type = var.instance_type
  subnet_id     = module.vpc2.private_subnets[count.index % length(module.vpc2.private_subnets)]

  key_name = aws_key_pair.mongo_key.key_name
  vpc_security_group_ids = [
    aws_security_group.mongodb.id,
  ]

  tags = {
    Name        = "mongo-${count.index}"
    Terraform   = "true"
    Environment = "stage"
  }
}

#############################################
  # Route53 Record
#############################################

resource "aws_route53_zone" "private_zone" {
  name = "dbox.locals."
}

resource "aws_route53_record" "mongo_records" {
  count   = 3
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "mongo-${count.index}-db.dbox.locals"
  type    = "A"
  ttl     = 300
  records = [
    aws_instance.mongo[count.index].private_ip
  ]
}

#############################################
  #bastion_instance
#############################################

resource "aws_instance" "bastion" {
  ami           = "ami-03a933af70fa97ad2"
  instance_type = "t2.small"
  subnet_id     = module.vpc2.public_subnets[0]

  key_name = aws_key_pair.mongo_key.key_name
  vpc_security_group_ids = [
    aws_security_group.mongodb.id,
  ]

  tags = {
    Name        = "bastion-instance"
    Terraform   = "true"
    Environment = "stage"
  }
}

#############################################
 # Download private key to bastion instance
#############################################

resource "null_resource" "private_key_bastion" {
  connection {
    host        = aws_instance.bastion.public_ip
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.ssh_key.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      "echo '${tls_private_key.ssh_key.private_key_pem}' > ~/private_key.pem",
      "chmod 600 ~/private_key.pem"
    ]
  }

  depends_on = [
    local_file.private_key,
    aws_instance.bastion,
  ]
}

#############################################
  #mongo_config
############################################

resource "null_resource" "mongodb_deploy" {
  depends_on = [
    aws_instance.mongo,
    aws_instance.bastion,
  ]

  count = 3

  connection {
    user          = "ubuntu"
    type          = "ssh"
    bastion_user  = "ubuntu"
    bastion_host  = aws_instance.bastion.public_ip
    bastion_private_key  = tls_private_key.ssh_key.private_key_pem
    agent         = false
    host          = aws_instance.mongo[count.index].private_ip
    private_key = tls_private_key.ssh_key.private_key_pem
  }

  provisioner "remote-exec" {
  inline = [
    "sudo apt-get install -y gnupg",
    "curl -fsSL https://www.mongodb.org/static/pgp/server-5.0.asc | sudo gpg --dearmor --output /usr/share/keyrings/mongodb-archive-keyring.gpg",
    "echo 'deb [signed-by=/usr/shareeyrings/mongodb-archive-keyring.gpg] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/5.0 multiverse' | sudo tee /etc/apt/sources.list.d/mongodb-org-5.0.list",
    "sudo apt-get update",
    "sudo apt-get install -y mongodb-org",
    "sudo sed -i 's/bindIp: .*/bindIp: 127.0.0.1, ${aws_instance.mongo[count.index].private_ip}/' /etc/mongod.conf",
    "sudo sed -i 's/#replication:/replication:\\n  replSetName: replicaset/' /etc/mongod.conf",
    "sudo systemctl restart mongod",
    "sleep 10",
    "mongo --eval 'rs.initiate({_id: \"replicaset\", members: [{_id: 0, host: \"${aws_instance.mongo[0].private_ip}:27017\"}, {_id: 1, host: \"${aws_instance.mongo[1].private_ip}:27017\"}, {_id: 2, host: \"${aws_instance.mongo[2].private_ip}:27017\"}]});'"
  ]
 }
}

