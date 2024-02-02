# create ecomc vpc
resource "aws_vpc" "ecomc_vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "ecomc-vpc"
  }
}
#create Ecomc public subnets
resource "aws_subnet" "ecomc_pub_sub_1" {
  vpc_id     = aws_vpc.ecomc_vpc.id
  cidr_block = "10.0.1.0/24"
availability_zone = "eu-west-2a"
  tags = {
    Name = "ecomc-pub-sub-1"
  } 
}
resource "aws_subnet" "ecomc_pub_sub_2" {
  vpc_id     = aws_vpc.ecomc_vpc.id
  cidr_block = "10.0.2.0/24"
availability_zone = "eu-west-2b"
  tags = {
    Name = "ecomc-pub-sub-2"
  }
  }
 
#aws ecomc public route table
resource "aws_route_table" "ecomc_pub_route_table" {
  vpc_id = aws_vpc.ecomc_vpc.id
  tags = {
  Name = "ecomc-route-table" }
}

#aws Ecomc route table association
resource "aws_route_table_association" "ecomc_pub-route-table-association-1" {
  subnet_id      = aws_subnet.ecomc_pub_sub_1.id
  route_table_id = aws_route_table.ecomc_pub_route_table.id
}
resource "aws_route_table_association" "ecomc_pub-route-table-association-2" {
  subnet_id      = aws_subnet.ecomc_pub_sub_2.id
  route_table_id = aws_route_table.ecomc_pub_route_table.id
}


# Ecomc_aws_internet_gateway
resource "aws_internet_gateway" "ecomc_igw" {
  vpc_id = aws_vpc.ecomc_vpc.id
  tags = {
    Name = "ecomc-igw"
  }
}

#aws route for igw & public route table 
resource "aws_route" "ecomc_pub_route_table_igw" {
 route_table_id = aws_route_table.ecomc_pub_route_table.id
 destination_cidr_block = "0.0.0.0/0"
 gateway_id             = aws_internet_gateway.ecomc_igw.id
}

# --- ECS Cluster ---

resource "aws_ecs_cluster" "ecomc" {
  name = "ecomc-cluster"
}

# --- ECS Node Role ---

data "aws_iam_policy_document" "ecs_node_doc" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_node_role" {
  name_prefix        = "Ecomc-ecs-node-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_node_doc.json
}

resource "aws_iam_role_policy_attachment" "ecs_node_role_policy" {
  role       = aws_iam_role.ecs_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# ALB Security Group: Edit to restrict access to the application
resource "aws_security_group" "lb" {
  name        = "ecomc-lb-sg"
  description = "controls access to the alb"
  vpc_id      = aws_vpc.ecomc_vpc.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }


  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# Traffic to the ECS cluster should only come from the ALB
resource "aws_security_group" "ecs_tasks" {
  name        = "ecomc-sg"
  description = "allow inbound access from the alb only"
  vpc_id      = aws_vpc.ecomc_vpc.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  }

# alb.tf

resource "aws_alb" "ecomc_alb" {
  name            = "ecomc-alb"
  subnets         = [aws_subnet.ecomc_pub_sub_1.id, aws_subnet.ecomc_pub_sub_2.id] 
  security_groups  = [aws_security_group.lb.id]          
} 
resource "aws_alb_target_group" "ecomc_tg" {
  name        = "ecomc-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ecomc_vpc.id
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = "/"
    unhealthy_threshold = "2"
  }
}

# Redirect all traffic from the ALB to the target group
resource "aws_alb_listener" "front_end" {
  load_balancer_arn = aws_alb.ecomc_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.ecomc_tg.arn
    type             = "forward"
  }
}


#Execution role
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com",
        },
      },
    ],
  })
}

resource "aws_db_subnet_group" "database_subnet_group" {
name   = "database-subnets"
subnet_ids =[aws_subnet.ecomc_pub_sub_1.id, aws_subnet.ecomc_pub_sub_2.id]
 description = "subnets for database instance"
 tags ={
  Name  ="database-subnets"
 } 
}



resource "aws_ecs_task_definition" "nginxdemos_task" {
  family = "nginxdemos"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu    = "256"
  memory = "512"

execution_role_arn = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "nginx-container"
      image     = "nginxdemos/hello"
      cpu       = 10
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    },

  ])

} 




resource "aws_ecs_service" "ecomc_service" {
  name            = "ecomic-service"
  cluster         = aws_ecs_cluster.ecomc.id
  task_definition = aws_ecs_task_definition.nginxdemos_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets          = [aws_subnet.ecomc_pub_sub_1.id, aws_subnet.ecomc_pub_sub_2.id]
    assign_public_ip = true 
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.ecomc_tg.arn
    container_name   = "nginx-container"
    container_port   = 80
  }

  depends_on = [aws_alb_listener.front_end]
}


