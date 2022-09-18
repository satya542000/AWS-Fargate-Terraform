#variables
variable "subnet_cidrs_public" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
  type = list
}
variable "subnet_cidrs_pri" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
  type = list
}
variable "availability_zones" {
  default = ["eu-west-2a", "eu-west-2b"]
}
data "aws_iam_role" "iam" {
  name = "AWSServiceRoleForECS"
}

#code
resource "aws_vpc" "vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  enable_dns_support= true
  enable_dns_hostnames= true
  tags = {
    Name = "SatyaFargateVPC"
  }
}
resource "aws_subnet" "pub" {
    count = length(var.subnet_cidrs_public)
    vpc_id     = aws_vpc.vpc.id
    availability_zone = var.availability_zones[count.index]
    map_public_ip_on_launch = "true"
    cidr_block = var.subnet_cidrs_public[count.index]
    tags = {
        Name = format("PublicSatyaFargate-%g",count.index)
    }
}
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "SatyaFargateIGW"
  }
}

resource "aws_route_table" "public" {
    vpc_id = aws_vpc.vpc.id  
    route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.igw.id
    }
    tags = {
      Name = "SatyaPublicRoute"
    }
}

resource "aws_route_table_association" "public" {
  count = length(var.subnet_cidrs_public)
  subnet_id      = element(aws_subnet.pub.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "eip" {
    vpc      = true
    depends_on = [aws_internet_gateway.igw]
    tags = {
        Name ="SatyaEIPFargate"
    }
}

resource "aws_nat_gateway" "ngw" {
    allocation_id = aws_eip.eip.id
    subnet_id     = aws_subnet.pub[0].id  
    tags = {
      Name = "NATSatyaFargate"
     }
}

resource "aws_subnet" "pri1" {
    vpc_id     = aws_vpc.vpc.id
    availability_zone = var.availability_zones[0]
    map_public_ip_on_launch = "false"
    cidr_block = var.subnet_cidrs_pri[0]
    tags = {
        Name = format("PrivateSatyaFargate-%g",1)
    }
}

resource "aws_subnet" "pri2" {
    vpc_id     = aws_vpc.vpc.id
    availability_zone = var.availability_zones[1]
    map_public_ip_on_launch = "false"
    cidr_block = var.subnet_cidrs_pri[1]
    tags = {
        Name = format("PrivateSatyaFargate-%g",2)
    }
}

resource "aws_route_table" "Pri" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.ngw.id
  }
  tags = {
    Name = "RoutePriSatyaFargate"
  }
}


resource "aws_route_table_association" "pri" {
  subnet_id      = aws_subnet.pri1.id
  route_table_id = aws_route_table.Pri.id
}

resource "aws_route_table_association" "pri2" {
  subnet_id      = aws_subnet.pri2.id
  route_table_id = aws_route_table.Pri.id
}


resource "aws_security_group" "sg" {
  name        = "FargateSatya-sg"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "FargateSatya-sg"
  }
}

resource "aws_lb" "alb" {
  name               = "SatyaAlbFargate"
  internal           = false
  # load_balancer_type = "application"
  security_groups    = [aws_security_group.sg.id]
  subnets            = [for subnet in aws_subnet.pub : subnet.id]

  enable_deletion_protection = false
  tags = {
    Environment = "SatyaAlbFargate"
  }
}
output "ip" {
  value = aws_lb.alb.dns_name
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
    # fixed_response {
    #   content_type = "text/plain"
    #   message_body = "Fixed response content"
    #   status_code  = "200"
    # }
  }
}

resource "aws_lb_target_group" "target_group" {
  name        = "satya-target-group"
  target_type = "ip"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    protocol            = "HTTP"
    matcher             = "200"
    path                = "/"
    interval            = 30
  }
}

# resource "aws_lb_target_group_attachment" "test" {
#   target_group_arn = aws_lb_target_group.target_group.arn
#   target_id        = aws_lb.alb.id
#   port             = 80
# }
resource "aws_ecr_repository" "image"{
  name                 = "satyafargateecr"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
resource "aws_ecs_cluster" "cluster" {
  name = "SatyaFargateCluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}


# resource "aws_ecs_task_definition" "task" {
#   family                   = "taskFargateSatya"
#   requires_compatibilities = ["FARGATE"]
#   network_mode             = "awsvpc"
#   cpu                      = 1024
#   memory                   = 2048
#   container_definitions    = jsonencode([
#     {
#       name      = "satyaFragateContainer"
#       image     = "mcr.microsoft.com/windows/servercore/iis"
#       cpu       = 10
#       memory    = 512
#       essential = true
#       portMappings = [
#         {
#           containerPort = 8080
#           protocol    = "tcp"
#           hostPort      = 8080
#         }
#       ]
#     }])
#  runtime_platform {
#     operating_system_family = "WINDOWS_SERVER_2019_CORE"
#     cpu_architecture        = "X86_64"
#   }
# }
resource "aws_ecs_task_definition" "task_definition" {
family  = "service"
requires_compatibilities = ["FARGATE"]
network_mode = "awsvpc"
cpu = 1024
memory  = 2048
 container_definitions = file("./service.json")
#jsonencode([
#     {
#       name      = "satyaFragateContainer"
#       image     = "mcr.microsoft.com/windows/servercore/iis"
#       cpu       = 1024
#       memory    = 2048
#       essential = true
#       portMappings = [
#         {
#           containerPort = 8080
#           hostPort      = 8080
#         }
#       ]
#     }
# ])

 runtime_platform {
 operating_system_family = "WINDOWS_SERVER_2019_CORE"
 cpu_architecture = "X86_64"
}
depends_on = [
  aws_ecs_cluster.cluster
]
}


resource "aws_ecs_service" "ecs" {
  name                 = "SatyaFargate-ecs"
  cluster              = aws_ecs_cluster.cluster.id
  task_definition      = aws_ecs_task_definition.task_definition.arn
  desired_count        = 2
  force_new_deployment = true
   launch_type     = "FARGATE"
  
  # ordered_placement_strategy {
  #   type  = "spread"
  #   field = "cpu"
  # }
  load_balancer {
    target_group_arn = aws_lb_target_group.target_group.arn
    container_name   = "satyaFragateContainer"
    container_port   = 80
  }
  # capacity_provider_strategy {
  #   capacity_provider = "FARGATE_SPOT"
  #   weight            = 100
  #   base              = 1
  # }
  # deployment_circuit_breaker{
  #   enable = true
  #   rollback = true
  # }
  # deployment_controller {
  #   type = "CODE_DEPLOY"
  # }
  network_configuration {
    security_groups  = [aws_security_group.sg2.id]
    subnets          = [aws_subnet.pri2.id, aws_subnet.pri1.id]
    assign_public_ip = false
  }
  # placement_constraints {
  #   type       = "memberOf"
  #   expression = "attribute:ecs.availability-zone in [us-west-2a, us-west-2b]"
  # }

}

resource "aws_security_group" "sg2" {
  name        = "satyasg"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    security_groups  = [aws_security_group.sg.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "satyafargatesg"
  }
}

# resource "aws_ecs_task_set" "example" {
#   service         = aws_ecs_service.ecs.id
#   cluster         = aws_ecs_cluster.cluster.id
#   task_definition = aws_ecs_task_definition.task_definition.id

#   load_balancer {
#     target_group_arn = aws_lb_target_group.target_group.arn
#     container_name   = "satyaFragateContainer"
#     container_port   = 8080
#   }
# }

