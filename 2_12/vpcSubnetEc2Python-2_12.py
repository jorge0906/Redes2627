import boto3

# Tarea 2_12 Redes
# Jorge Escrich Laorden

# Región y zona de disponibilidad donde se crean los recursos
REGION = 'us-east-1'
AZ = 'us-east-1a'

# Direccionamiento usado en el script
VPC_CIDR = '172.16.0.0/16'
PUBLICSUBNET_CIDR = '172.16.0.0/20'
PRIVATESUBNET_CIDR = '172.16.64.0/20'

# IPs privadas de las instancias 
EC2_PUBLIC_IP = '172.16.0.100'
EC2_PRIVATE_IP = '172.16.64.100'

# Imagen y tipo de instancia
AMI_ID = 'ami-0b6d9d3d33ba97d99'
INSTANCE_TYPE = 't3.micro'
KEY_NAME = 'vockey'


TAGS_PRUEBA = [{'Key': 'Type', 'Value': 'prueba'}]


def etiquetar(ec2, resource_id, nombre):
    """Asigna a un recurso las etiquetas Name y Type=prueba."""
    ec2.create_tags(
        Resources=[resource_id],
        Tags=[{'Key': 'Name', 'Value': nombre}] + TAGS_PRUEBA
    )


def crear_vpc(ec2):
    """Crea la VPC con DNS support y DNS hostnames habilitados."""
    vpc = ec2.create_vpc(CidrBlock=VPC_CIDR)
    vpc_id = vpc['Vpc']['VpcId']
    print(f"✅ VPC creada con ID: {vpc_id} ({VPC_CIDR})")

    # Habilitar DNS support y DNS hostnames
    ec2.modify_vpc_attribute(VpcId=vpc_id, EnableDnsSupport={'Value': True})
    ec2.modify_vpc_attribute(VpcId=vpc_id, EnableDnsHostnames={'Value': True})

    etiquetar(ec2, vpc_id, 'Script-VPC')
    print("🌐 DNS habilitado y etiquetas asignadas.")
    return vpc_id


def crear_subnet(ec2, vpc_id, cidr_block, nombre):
    """Crea una subred en la AZ indicada y la etiqueta."""
    subnet = ec2.create_subnet(
        VpcId=vpc_id,
        CidrBlock=cidr_block,
        AvailabilityZone=AZ
    )
    subnet_id = subnet['Subnet']['SubnetId']

    etiquetar(ec2, subnet_id, nombre)
    print(f"✅ Subred {nombre} creada con ID: {subnet_id} ({cidr_block}, {AZ})")
    return subnet_id


def crear_internet_gateway(ec2, vpc_id):
    """Crea el Internet Gateway y lo adjunta a la VPC."""
    igw = ec2.create_internet_gateway()
    igw_id = igw['InternetGateway']['InternetGatewayId']

    ec2.attach_internet_gateway(
        InternetGatewayId=igw_id,
        VpcId=vpc_id
    )
    etiquetar(ec2, igw_id, 'Script-IGW')

    print(f"✅ Internet Gateway creado y adjuntado a la VPC: {igw_id}")
    return igw_id


def crear_tabla_rutas_publica(ec2, vpc_id, igw_id, subnet_id):
    """Tabla de rutas con salida directa a Internet (0.0.0.0/0 -> IGW)."""
    route_table = ec2.create_route_table(VpcId=vpc_id)
    route_table_id = route_table['RouteTable']['RouteTableId']

    ec2.create_route(
        RouteTableId=route_table_id,
        DestinationCidrBlock='0.0.0.0/0',
        GatewayId=igw_id
    )

    ec2.associate_route_table(
        RouteTableId=route_table_id,
        SubnetId=subnet_id
    )
    etiquetar(ec2, route_table_id, 'Script-RouteTable-Public')

    print(f"✅ Tabla de rutas publica creada (0.0.0.0/0 -> IGW) y asociada: {route_table_id}")
    return route_table_id


def crear_nat_gateway(ec2, public_subnet_id):
    """Reserva una Elastic IP y crea el NAT Gateway en la subred publica."""
    eip = ec2.allocate_address(Domain='vpc')
    eip_alloc_id = eip['AllocationId']
    etiquetar(ec2, eip_alloc_id, 'Script-EIP-NAT')
    print(f"✅ Elastic IP reservada: {eip_alloc_id} ({eip['PublicIp']})")

    nat_gw = ec2.create_nat_gateway(
        SubnetId=public_subnet_id,
        AllocationId=eip_alloc_id
    )
    nat_gw_id = nat_gw['NatGateway']['NatGatewayId']
    etiquetar(ec2, nat_gw_id, 'Script-NATGW')
    print(f"✅ NAT Gateway creado en la subred publica: {nat_gw_id}")

    # Esperar a que el NAT Gateway este disponible antes de crear la ruta
    print("⏳ Esperando a que el NAT Gateway este disponible...")
    ec2.get_waiter('nat_gateway_available').wait(NatGatewayIds=[nat_gw_id])
    print("✅ NAT Gateway disponible.")

    return nat_gw_id, eip_alloc_id


def crear_tabla_rutas_privada(ec2, vpc_id, nat_gw_id, subnet_id):
    """Tabla de rutas con salida a Internet a traves del NAT Gateway."""
    route_table = ec2.create_route_table(VpcId=vpc_id)
    route_table_id = route_table['RouteTable']['RouteTableId']

    ec2.create_route(
        RouteTableId=route_table_id,
        DestinationCidrBlock='0.0.0.0/0',
        NatGatewayId=nat_gw_id
    )

    ec2.associate_route_table(
        RouteTableId=route_table_id,
        SubnetId=subnet_id
    )
    etiquetar(ec2, route_table_id, 'Script-RouteTable-Private')

    print(f"✅ Tabla de rutas privada creada (0.0.0.0/0 -> NAT) y asociada: {route_table_id}")
    return route_table_id


def crear_security_group(ec2, vpc_id):
    """SG unico para ambas instancias: SSH desde Internet y trafico entre ellas."""
    sg = ec2.create_security_group(
        GroupName='Script-SG',
        Description='Security group for Script',
        VpcId=vpc_id
    )
    sg_id = sg['GroupId']

    ec2.authorize_security_group_ingress(
        GroupId=sg_id,
        IpPermissions=[
            # SSH a la instancia publica desde cualquier origen
            {
                'IpProtocol': 'tcp',
                'FromPort': 22,
                'ToPort': 22,
                'IpRanges': [{'CidrIp': '0.0.0.0/0'}]
            },
            # SSH entre las dos instancias (mismo SG)
            {
                'IpProtocol': 'tcp',
                'FromPort': 22,
                'ToPort': 22,
                'UserIdGroupPairs': [{'GroupId': sg_id}]
            },
            # Ping (ICMP) entre las dos instancias, para comprobar conectividad
            {
                'IpProtocol': 'icmp',
                'FromPort': -1,
                'ToPort': -1,
                'UserIdGroupPairs': [{'GroupId': sg_id}]
            }
        ]
    )
    etiquetar(ec2, sg_id, 'Script-SG')

    print(f"✅ Security Group creado con ID: {sg_id} (SSH abierto + trafico interno)")
    return sg_id


def crear_ec2_instance(ec2, subnet_id, security_group_id, private_ip, nombre,
                       ip_publica=False):
    """Crea una instancia EC2 en la subred indicada."""
    parametros = dict(
        ImageId=AMI_ID,
        InstanceType=INSTANCE_TYPE,
        MaxCount=1,
        MinCount=1,
        SubnetId=subnet_id,
        PrivateIpAddress=private_ip,
        SecurityGroupIds=[security_group_id],
        KeyName=KEY_NAME
    )

    # Solo la instancia publica recibe IP publica
    if ip_publica:
        parametros['NetworkInterfaces'] = [{
            'DeviceIndex': 0,
            'SubnetId': subnet_id,
            'PrivateIpAddress': private_ip,
            'Groups': [security_group_id],
            'AssociatePublicIpAddress': True
        }]
        # Si se usa NetworkInterfaces no se pueden repetir estos parametros
        for clave in ('SubnetId', 'PrivateIpAddress', 'SecurityGroupIds'):
            parametros.pop(clave)

    instance = ec2.run_instances(**parametros)
    instance_id = instance['Instances'][0]['InstanceId']

    etiquetar(ec2, instance_id, nombre)
    print(f"✅ Instancia {nombre} creada: {instance_id} (IP privada {private_ip})")
    return instance_id


if __name__ == "__main__":
    ec2 = boto3.client('ec2', region_name=REGION)

    # 1. VPC
    vpc_id = crear_vpc(ec2)

    # 2. Subred publica y subred privada 
    subnet_public_id = crear_subnet(ec2, vpc_id, PUBLICSUBNET_CIDR, 'Script-Subnet-Public')
    subnet_private_id = crear_subnet(ec2, vpc_id, PRIVATESUBNET_CIDR, 'Script-Subnet-Private')

    # 3. Internet Gateway + tabla de rutas publica
    igw_id = crear_internet_gateway(ec2, vpc_id)
    rt_public_id = crear_tabla_rutas_publica(ec2, vpc_id, igw_id, subnet_public_id)

    # 4. NAT Gateway en la subred publica + tabla de rutas privada
    nat_gw_id, eip_alloc_id = crear_nat_gateway(ec2, subnet_public_id)
    rt_private_id = crear_tabla_rutas_privada(ec2, vpc_id, nat_gw_id, subnet_private_id)

    # 5. Security Group
    sg_id = crear_security_group(ec2, vpc_id)

    # 6. Instancia publica (con IP publica, salida directa por IGW)
    instance_public_id = crear_ec2_instance(
        ec2, subnet_public_id, sg_id, EC2_PUBLIC_IP,
        'Script-Instance-Public', ip_publica=True
    )

    # 7. Instancia privada (sin IP publica, salida por NAT)
    instance_private_id = crear_ec2_instance(
        ec2, subnet_private_id, sg_id, EC2_PRIVATE_IP,
        'Script-Instance-Private', ip_publica=False
    )

    # 8. Esperar a que ambas instancias esten en ejecucion
    print("⏳ Esperando a que las instancias esten running...")
    ec2.get_waiter('instance_running').wait(InstanceIds=[instance_public_id, instance_private_id])

    # 9. Resumen final
    public_ip = ec2.describe_instances(InstanceIds=[instance_public_id])[
        'Reservations'][0]['Instances'][0].get('PublicIpAddress', 'N/A')

    print("\n===== RESUMEN =====")
    print(f"VPC:             {vpc_id} ({VPC_CIDR})")
    print(f"Subred publica:  {subnet_public_id} ({PUBLICSUBNET_CIDR}) -> IGW {igw_id}")
    print(f"Subred privada:  {subnet_private_id} ({PRIVATESUBNET_CIDR}) -> NAT {nat_gw_id} (EIP {eip_alloc_id})")
    print(f"EC2 publica:     {instance_public_id} (privada {EC2_PUBLIC_IP} / publica {public_ip})")
    print(f"EC2 privada:     {instance_private_id} (privada {EC2_PRIVATE_IP}, sin IP publica)")
    print()
