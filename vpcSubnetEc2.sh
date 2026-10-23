#!/bin/bash

#Jorge Escrich Laorden

echo "Menú de opciones:"
echo "1 Eliminar VPC, Subnet e Instancia EC2"
echo "2 Crear VPC, Subnet e Instancia EC2"
echo "Ingrese el número de la opción que desea ejecutar (1 o 2):"
read opcion

if [ $opcion -ne 1 ] && [ $opcion -ne 2 ]; then
    echo "Opción inválida. Por favor, elija 1 o 2."
    exit 1
fi


if [ $opcion -eq 1 ]; then
    
# OPCIÓN 1: ELIMINAR 
echo "Buscando y eliminando recursos por etiqueta..."

# 1. Buscar y eliminar la instancia EC2 por nombre Script-Instance
INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=Script-Instance" "Name=instance-state-name,Values=pending,running,stopped,stopping" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)

if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
    echo "Terminando instancia EC2: $INSTANCE_ID"
    aws ec2 terminate-instances --instance-ids $INSTANCE_ID > /dev/null 2>&1
    echo "Esperando a que la instancia se termine por completo..."
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID > /dev/null 2>&1
else
    echo "No se encontró ninguna instancia activa con el nombre Script-Instance."
fi

# 2. Buscar y eliminar la Subnet por nombre
SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=Script-Subnet" \
    --query "Subnets[].SubnetId" \
    --output text)

if [ -n "$SUBNET_ID" ] && [ "$SUBNET_ID" != "None" ]; then
    echo "Eliminando Subnet: $SUBNET_ID"
    aws ec2 delete-subnet --subnet-id $SUBNET_ID
else
    echo "No se encontró ninguna Subnet con el nombre Script-Subnet."
fi

# 3. Buscar y eliminar la VPC por nombre
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=Script-VPC" \
    --query "Vpcs[].VpcId" \
    --output text)

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    echo "Eliminando VPC: $VPC_ID"
    aws ec2 delete-vpc --vpc-id $VPC_ID
else
    echo "No se encontró ninguna VPC con el nombre Script-VPC."
fi

fi



#OPCIÓN 2: CREAR 

if [ $opcion -eq 2 ]; then
    echo "Creando VPC, Subnet e Instancia EC2"



VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
--query 'Vpc.VpcId' \
--tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=Script-VPC},{Key=Environment,Value=Script}]'  \
--output text) 
echo $VPC_ID


#Crear Subnet
SUBNET_ID=$(aws ec2 create-subnet \
--vpc-id $VPC_ID \
--cidr-block 10.0.1.0/24 \
--query 'Subnet.SubnetId' \
--tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Script-Subnet},{Key=Environment,Value=Script}]' \
--output text) 
echo $SUBNET_ID



#Crear intancia EC2
INSTANCE_ID=$(aws ec2 run-instances \
--image-id ami-0b6d9d3d33ba97d99 \
--count 1 --instance-type t2.micro \
--key-name vockey --subnet-id $SUBNET_ID \
--query 'Instances[0].InstanceId' \
--associate-public-ip-address \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Script-Instance},{Key=Environment,Value=Script}]' \
--output text) 
echo $INSTANCE_ID

fi

exit 0
