terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 3.0"
        }
    }
}

# Define input variables
variable "region" {}
variable availability_zone {}
variable "ami" {}
variable "bucket_name" {}
variable database_name {}
variable database_user {}
variable database_pass {}
variable admin_user {}
variable admin_pass {}
variable "key_pair_path" {
    default = "~/.ssh/id_rsa.pub"
}

# Configure the AWS Provider
provider "aws" {
    region = var.region
    profile = "default"
}

resource "aws_key_pair" "deployer" {
    key_name   = "deployer-key"
    public_key = file(var.key_pair_path)
}

# 1. aws_vpc
resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "development"
    }
}

# 2. aws_subnet
resource "aws_subnet" "app_subnet" {
    vpc_id     = aws_vpc.main.id
    cidr_block = "10.0.1.0/24"
    availability_zone = var.availability_zone
    map_public_ip_on_launch = true
    tags = {
        Name = "app-subnet"
    }
}
resource "aws_subnet" "db_subnet" {
    vpc_id     = aws_vpc.main.id
    cidr_block = "10.0.2.0/24"
    availability_zone = var.availability_zone
    map_public_ip_on_launch = false
    tags = {
        Name = "db-subnet"
    }
}
resource "aws_subnet" "inside_subnet" {
    vpc_id     = aws_vpc.main.id
    cidr_block = "10.0.3.0/24"
    availability_zone = var.availability_zone
    map_public_ip_on_launch = false
    tags = {
        Name = "subnet-between-two-instance"
    }
}

# 3. aws_network_interface
resource "aws_network_interface" "app_pub" {
    subnet_id       = aws_subnet.app_subnet.id
    private_ips     = ["10.0.1.50"]
    security_groups = [aws_security_group.app_sec.id]
}
resource "aws_network_interface" "app_between" {
    subnet_id       = aws_subnet.inside_subnet.id
    private_ips     = ["10.0.3.50"]
}
resource "aws_network_interface" "db_priv" {
    subnet_id       = aws_subnet.db_subnet.id
    private_ips     = ["10.0.2.50"]
}
resource "aws_network_interface" "db_between" {
    subnet_id       = aws_subnet.inside_subnet.id
    private_ips     = ["10.0.3.51"]
    security_groups = [aws_security_group.db_sec.id]
}

# 4. aws_security_group
resource "aws_security_group" "app_sec" {
    vpc_id      = aws_vpc.main.id
    tags = {
        Name = "app-security-group"
    }
}
resource "aws_security_group" "db_sec" {
    vpc_id      = aws_vpc.main.id
    tags = {
        Name = "database-security-group"
    }
}

# 5. aws_security_group_rule
resource "aws_security_group_rule" "app_ssh" {
    type              = "ingress"
    from_port         = 22
    to_port           = 22
    protocol          = "tcp"
    cidr_blocks       = ["0.0.0.0/0"]
    security_group_id = aws_security_group.app_sec.id
}
resource "aws_security_group_rule" "app_http" {
    type              = "ingress"
    from_port         = 80
    to_port           = 80
    protocol          = "tcp"
    cidr_blocks       = ["0.0.0.0/0"]
    security_group_id = aws_security_group.app_sec.id
}
resource "aws_security_group_rule" "app_https" {
    type              = "ingress"
    from_port         = 443
    to_port           = 443
    protocol          = "tcp"
    cidr_blocks       = ["0.0.0.0/0"]
    security_group_id = aws_security_group.app_sec.id
}
resource "aws_security_group_rule" "app_out" {
    type              = "egress"
    from_port         = 0
    to_port           = 0
    protocol          = "-1"
    cidr_blocks       = ["0.0.0.0/0"]
    security_group_id = aws_security_group.app_sec.id
}
resource "aws_security_group_rule" "db_mariaport" {
    type              = "ingress"
    from_port         = 3306
    to_port           = 3306
    protocol          = "tcp"
    cidr_blocks       = ["10.0.3.50/32"]
    security_group_id = aws_security_group.db_sec.id
}
resource "aws_security_group_rule" "db_out" {
    type              = "egress"
    from_port         = 0
    to_port           = 0
    protocol          = "-1"
    cidr_blocks       = ["0.0.0.0/0"]
    security_group_id = aws_security_group.db_sec.id
}

# 6. aws_instance
resource "aws_instance" "app" {
    ami           = var.ami
    instance_type = "t2.micro"
    availability_zone = var.availability_zone
    key_name = aws_key_pair.deployer.id
    network_interface {
        device_index = 0
        network_interface_id = aws_network_interface.app_pub.id
    }
    network_interface {
        device_index = 1
        network_interface_id = aws_network_interface.app_between.id
    }
    user_data = data.template_file.nextcloud-init.rendered
    tags = {
        Name = "app"
    }
    depends_on = [aws_instance.database]
}
resource "aws_instance" "database" {
    ami           = var.ami
    instance_type = "t2.micro"
    availability_zone = var.availability_zone
    key_name = aws_key_pair.deployer.id
    network_interface {
        device_index = 0
        network_interface_id = aws_network_interface.db_priv.id
    }
    network_interface {
        device_index = 1
        network_interface_id = aws_network_interface.db_between.id
    }
    user_data = data.template_file.db-init.rendered
    tags = {
        Name = "database"
    }
}

# 7. aws_internet_gateway
resource "aws_internet_gateway" "app_gw" {
    vpc_id = aws_vpc.main.id
    tags = {
        Name = "app-gw"
    }
}

# 8. aws_nat_gateway
resource "aws_nat_gateway" "db_gw" {
    allocation_id   = aws_eip.db_eip.id
    subnet_id       = aws_subnet.app_subnet.id
}

# 9. aws_route
resource "aws_route" "app_r" {
    route_table_id          = aws_route_table.app_rt.id
    destination_cidr_block  = "0.0.0.0/0"
    gateway_id              = aws_internet_gateway.app_gw.id
    depends_on              = [aws_route_table.app_rt]
}
resource "aws_route" "db_r" {
    route_table_id            = aws_route_table.db_rt.id
    destination_cidr_block    = "0.0.0.0/0"
    nat_gateway_id            = aws_nat_gateway.db_gw.id
    depends_on                = [aws_route_table.db_rt]
}

# 10. aws_route_table
resource "aws_route_table" "app_rt" {
    vpc_id = aws_vpc.main.id
    tags = {
        Name = "app-route-table"
    }
}
resource "aws_route_table" "db_rt" {
    vpc_id = aws_vpc.main.id
    tags = {
        Name = "database-route-table"
    }
}

# 11. aws_route_table_association
resource "aws_route_table_association" "app_rta" {
    subnet_id      = aws_subnet.app_subnet.id
    route_table_id = aws_route_table.app_rt.id
}
resource "aws_route_table_association" "db_rta" {
    subnet_id      = aws_subnet.db_subnet.id
    route_table_id = aws_route_table.db_rt.id
}

# 12. aws_eip
resource "aws_eip" "app_eip" {
    vpc                         = true
    network_interface           = aws_network_interface.app_pub.id
    associate_with_private_ip   = aws_network_interface.app_pub.private_ip
}
resource "aws_eip" "db_eip" {
    vpc = true
}

# 13. aws_s3_bucket
resource "aws_s3_bucket" "storage" {
    bucket = var.bucket_name
    acl = "private"
    force_destroy = true
}

# 14. aws_iam_access_key
resource "aws_iam_access_key" "buck" {
    user    = aws_iam_user.buck.name
}

# 15. aws_iam_user
resource "aws_iam_user" "buck" {
    name = "buck"
}

# 16. aws_iam_policy
resource "aws_iam_user_policy" "buck_ro" {
    name = "buck_policy"
    user = aws_iam_user.buck.name
    policy = jsonencode({
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "s3:*"
                ],
                "Resource": "*"
            }
        ]
    })
}

# Disclaimer: this part and scripts are applied from https://github.com/kaisoz/terraform-nextcloud-ec2-rds-s3 
# data "template_cloudinit_config" "nextcloud-init" {
#     gzip          = false
#     base64_encode = false
#     part {
#         content_type = "text/x-shellscript"
#         content = templatefile("instance-scripts/nextcloud1.sh", {})
#     }
#     part {
#         content_type = "text/x-shellscript"
#         content = templatefile("instance-scripts/s3.sh", {
#             aws_region = var.region,
#             s3_bucket_name = var.bucket_name,
#             user_access_key = aws_iam_access_key.buck.id,
#             user_secret_key = aws_iam_access_key.buck.secret
#         })
#     }
#     part {
#         content_type = "text/x-shellscript"
#         content = templatefile("instance-scripts/nextcloud2.sh", {})
#     }
#     part {
#         content_type = "text/x-shellscript"
#         content = templatefile("instance-scripts/nextcloud3.sh", {
#             database_name = var.database_name,
#             database_user = var.database_user,
#             database_pass = var.database_pass,
#             database_adr = aws_network_interface.db_between.private_ip,
#             admin_user = var.admin_user,
#             admin_pass = var.admin_pass,
#         })
#     }
#     part {
#         content_type = "text/x-shellscript"
#         content = templatefile("instance-scripts/nextcloud4.sh", {})
#     }
# }

# output "run_yourself" {
#     value = data.template_file.nextcloud-init.rendered
# }

output "ip" {
    value = aws_instance.app.public_ip
}

data "template_file" "nextcloud-init" {
    template = file("instance-scripts/nextcloud.sh")
    vars = {
        aws_region = var.region,
        s3_bucket_name = var.bucket_name,
        user_access_key = aws_iam_access_key.buck.id,
        user_secret_key = aws_iam_access_key.buck.secret,
        database_name = var.database_name,
        database_user = var.database_user,
        database_pass = var.database_pass,
        database_adr = "10.0.3.51:3306",
        admin_user = var.admin_user,
        admin_pass = var.admin_pass,
    }
}

data "template_file" "db-init" {
    template = file("instance-scripts/mariadb.sh")
    vars = {
        database_root_pass = var.database_pass
        database_user      = var.database_user
        database_name      = var.database_name
        database_pass      = var.database_pass
    }
}
