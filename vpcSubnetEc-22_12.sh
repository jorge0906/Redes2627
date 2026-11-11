#!/bin/bash

#Tarea 2_11 Redes
#Jorge Escrich Laorden

# Direccionamiento usado en el script
VPC_CIDR="172.16.0.0/16"
PUBLICSUBNET_CIDR="172.16.0.0/20"
PRIVATESUBNET_CIDR="172.16.64.0/20"
EC2_PRIVATE_IP="172.16.0.100"

EC2_PUBLICSUBNET_IP="172.16.0.100/20"
EC2_PRIVATESUBNET_IP="172.64.0.100/20"
AZ="us-east-1a"


#CREAR 


VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR \
--query 'Vpc.VpcId' \
--tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=Script-VPC},{Key=Type,Value=prueba}]' \
--output text) 
echo "VPC: $VPC_ID"

#Dns support and DNS hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support "{\"Value\":true}"
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames "{\"Value\":true}"

#Crear Subnet publica
SUBNET_ID=$(aws ec2 create-subnet \
--vpc-id $VPC_ID \
--cidr-block $PUBLICSUBNET_CIDR \
--availability-zone $AZ \
--query 'Subnet.SubnetId' \
--tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Script-Subnet},{Key=Type,Value=prueba}]' \
--output text) 
echo "Subnet: $SUBNET_ID ($AZ)"

#Crear Subnet privada
SUBNET_ID2=$(aws ec2 create-subnet \
--vpc-id $VPC_ID \
--cidr-block $PRIVATESUBNET_CIDR \
--availability-zone $AZ \
--query 'Subnet.SubnetId' \
--tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Script-Subnet2},{Key=Type,Value=prueba}]' \
--output text)
echo "Subnet: $SUBNET_ID2 ($AZ)"

# Crear Internet Gateway y asociarlo a la VPC
IGW_ID=$(aws ec2 create-internet-gateway \
--query 'InternetGateway.InternetGatewayId' \
--tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=Script-IGW},{Key=Type,Value=prueba}]' \
--output text)
echo "Internet Gateway: $IGW_ID"

aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

# Crear tabla de rutas y asociarla a la subnet
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
--vpc-id $VPC_ID \
--query 'RouteTable.RouteTableId' \
--tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Script-RouteTable},{Key=Type,Value=prueba}]' \
--output text)
echo "Tabla de rutas: $ROUTE_TABLE_ID"

# Ruta por defecto hacia el Internet Gateway
aws ec2 create-route \
--route-table-id $ROUTE_TABLE_ID \
--destination-cidr-block 0.0.0.0/0 \
--gateway-id $IGW_ID

# Asociar la tabla de rutas a la subnet
aws ec2 associate-route-table \
--route-table-id $ROUTE_TABLE_ID \
--subnet-id $SUBNET_ID


# Crear Security Group
SG_ID=$(aws ec2 create-security-group \
--group-name Script-SG \
--description "Security group for Script" \
--vpc-id $VPC_ID \
--query 'GroupId' \
--tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=Script-SG},{Key=Type,Value=prueba}]' \
--output text)
echo "Security Group: $SG_ID"

aws ec2 authorize-security-group-ingress \
--group-id $SG_ID \
--protocol tcp \
--port 22 \
--cidr 0.0.0.0/0 


#Crear intancia EC2 de la subnet publica
INSTANCE_ID=$(aws ec2 run-instances \
--image-id ami-0b6d9d3d33ba97d99 \
--count 1 --instance-type t3.micro \
--key-name vockey --subnet-id $SUBNET_ID \
--private-ip-address $EC2_PRIVATE_IP \
--query 'Instances[0].InstanceId' \
--associate-public-ip-address \
--security-group-ids $SG_ID \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Script-Instance},{Key=Type,Value=prueba}]' \
--output text) 
echo "Instancia EC2: $INSTANCE_ID (IP privada $EC2_PUBLIC_IP)"

#Crear intancia EC2 de la subnet privada
INSTANCE_ID2=$(aws ec2 run-instances \
--image-id ami-0b6d9d3d33ba97d99 \
--count 1 --instance-type t3.micro \
--key-name vockey --subnet-id $SUBNET_ID2 \
--private-ip-address $EC2_PRIVATESUBNET_IP \
--query 'Instances[0].InstanceId' \
--associate-public-ip-address \
--security-group-ids $SG_ID \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Script-Instance2},{Key=Type,Value=prueba}]' \
--output text)
echo "Instancia EC2: $INSTANCE_ID2 (IP privada $EC2_PRIVATESUBNET_IP)"      






exit 0
