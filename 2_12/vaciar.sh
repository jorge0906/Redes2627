#!/bin/bash
# Elimina todos los recursos creados con la etiqueta Type=prueba
# (Instancias EC2, NAT Gateway, Elastic IP, Security Group, Tablas de rutas,
#  Internet Gateway, Subredes y VPC)

echo "Buscando y eliminando recursos con la etiqueta Type=prueba..."

# 1. Buscar y eliminar las instancias EC2 por etiqueta
INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=prueba" "Name=instance-state-name,Values=pending,running,stopped,stopping" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)

if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then
    echo "Terminando instancias EC2: $INSTANCE_IDS"
    aws ec2 terminate-instances --instance-ids $INSTANCE_IDS > /dev/null 2>&1
    echo "Esperando a que las instancias se terminen por completo..."
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS > /dev/null 2>&1
else
    echo "No se encontró ninguna instancia activa con el tipo prueba."
fi

# 2. Buscar y eliminar el Security Group por etiqueta
SG_IDS=$(aws ec2 describe-security-groups \
    --filters "Name=tag:Type,Values=prueba" \
    --query "SecurityGroups[].GroupId" \
    --output text)

if [ -n "$SG_IDS" ] && [ "$SG_IDS" != "None" ]; then
    for SG_ID in $SG_IDS; do
        echo "Eliminando Security Group: $SG_ID"
        # El grupo puede tardar unos segundos en liberarse al terminar la instancia
        for intento in 1 2 3 4 5; do
            aws ec2 delete-security-group --group-id $SG_ID && break
            echo "Reintentando en 5 segundos..."
            sleep 5
        done
    done
else
    echo "No se encontró ningún Security Group con el tipo prueba."
fi

# 3. Buscar y eliminar los NAT Gateway (deben borrarse antes que subredes y VPC)
NAT_GW_IDS=$(aws ec2 describe-nat-gateways \
    --filter "Name=tag:Type,Values=prueba" \
    --query "NatGateways[?State!='deleted'].NatGatewayId" \
    --output text)

# Guardamos las Elastic IP de esos NAT antes de borrarlos, para liberarlas luego
NAT_ALLOC_IDS=""
if [ -n "$NAT_GW_IDS" ] && [ "$NAT_GW_IDS" != "None" ]; then
    NAT_ALLOC_IDS=$(aws ec2 describe-nat-gateways \
        --nat-gateway-ids $NAT_GW_IDS \
        --query "NatGateways[].NatGatewayAddresses[].AllocationId" \
        --output text)

    for NAT_ID in $NAT_GW_IDS; do
        echo "Eliminando NAT Gateway: $NAT_ID"
        aws ec2 delete-nat-gateway --nat-gateway-id $NAT_ID > /dev/null 2>&1
    done

    echo "Esperando a que los NAT Gateway se eliminen por completo..."
    for NAT_ID in $NAT_GW_IDS; do
        aws ec2 wait nat-gateway-deleted --nat-gateway-ids $NAT_ID > /dev/null 2>&1
    done
else
    echo "No se encontró ningún NAT Gateway con el tipo prueba."
fi

# 4. Buscar y liberar las Elastic IP (primero hay que eliminar el NAT que las usa)
EIP_ALLOC_IDS=$(aws ec2 describe-addresses \
    --filters "Name=tag:Type,Values=prueba" \
    --query "Addresses[].AllocationId" \
    --output text)

# Unimos las etiquetadas con las que colgaban de los NAT Gateway, sin duplicados
ALL_ALLOC_IDS=$(echo "$EIP_ALLOC_IDS $NAT_ALLOC_IDS" | tr ' ' '\n' | grep -v '^$' | grep -vx 'None' | sort -u)

if [ -n "$ALL_ALLOC_IDS" ]; then
    for ALLOC_ID in $ALL_ALLOC_IDS; do
        echo "Liberando Elastic IP: $ALLOC_ID"
        aws ec2 release-address --allocation-id $ALLOC_ID
    done
else
    echo "No se encontró ninguna Elastic IP con el tipo prueba."
fi

# 5. Buscar y eliminar las tablas de rutas por etiqueta
ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Type,Values=prueba" \
    --query "RouteTables[].RouteTableId" \
    --output text)

if [ -n "$ROUTE_TABLE_IDS" ] && [ "$ROUTE_TABLE_IDS" != "None" ]; then
    for RT_ID in $ROUTE_TABLE_IDS; do
        echo "Procesando tabla de rutas: $RT_ID"

        # Desasociar la tabla de rutas de la subred (la asociación principal no se toca)
        ASSOC_IDS=$(aws ec2 describe-route-tables \
            --route-table-ids $RT_ID \
            --query "RouteTables[].Associations[?Main==\`false\`].RouteTableAssociationId" \
            --output text)

        for ASSOC_ID in $ASSOC_IDS; do
            echo " Desasociando $ASSOC_ID"
            aws ec2 disassociate-route-table --association-id $ASSOC_ID
        done

        echo " Eliminando tabla de rutas: $RT_ID"
        aws ec2 delete-route-table --route-table-id $RT_ID
    done
else
    echo "No se encontró ninguna tabla de rutas con el tipo prueba."
fi

# 6. Buscar, desasociar y eliminar el Internet Gateway por etiqueta
IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=tag:Type,Values=prueba" \
    --query "InternetGateways[].InternetGatewayId" \
    --output text)

if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
    for GW_ID in $IGW_ID; do
        VPC_ATTACHED=$(aws ec2 describe-internet-gateways \
            --internet-gateway-ids $GW_ID \
            --query "InternetGateways[].Attachments[].VpcId" \
            --output text)

        if [ -n "$VPC_ATTACHED" ] && [ "$VPC_ATTACHED" != "None" ]; then
            echo "Desasociando Internet Gateway $GW_ID de la VPC $VPC_ATTACHED"
            aws ec2 detach-internet-gateway --internet-gateway-id $GW_ID --vpc-id $VPC_ATTACHED
        fi

        echo "Eliminando Internet Gateway: $GW_ID"
        aws ec2 delete-internet-gateway --internet-gateway-id $GW_ID
    done
else
    echo "No se encontró ningún Internet Gateway con el tipo prueba."
fi

# 7. Buscar y eliminar las Subnets por etiqueta
SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=tag:Type,Values=prueba" \
    --query "Subnets[].SubnetId" \
    --output text)

if [ -n "$SUBNET_IDS" ] && [ "$SUBNET_IDS" != "None" ]; then
    for SUB_ID in $SUBNET_IDS; do
        echo "Eliminando Subnet: $SUB_ID"
        aws ec2 delete-subnet --subnet-id $SUB_ID
    done
else
    echo "No se encontró ninguna Subnet con el tipo prueba."
fi

# 8. Buscar y eliminar la VPC por etiqueta
VPC_IDS=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Type,Values=prueba" \
    --query "Vpcs[].VpcId" \
    --output text)

if [ -n "$VPC_IDS" ] && [ "$VPC_IDS" != "None" ]; then
    for VPC in $VPC_IDS; do
        echo "Eliminando VPC: $VPC"
        for intento in 1 2 3 4 5; do
            aws ec2 delete-vpc --vpc-id $VPC && break
            echo "Reintentando en 5 segundos..."
            sleep 5
        done
    done
else
    echo "No se encontró ninguna VPC con el tipo prueba."
fi

echo "Proceso completado."
exit 0
