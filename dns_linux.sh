#!/bin/bash
# script para configurar el servidor DNS con bind9
# dominio: reprobados.com

DOMAIN="reprobados.com"
ZONE_FILE="/var/cache/bind/db.${DOMAIN}"
NAMED_LOCAL="/etc/bind/named.conf.local"

# colores para que se vea mas claro en la terminal
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# primero verificar que se este corriendo como root
# si no, de nada sirve continuar
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}error: necesitas correr esto con sudo${NC}"
        exit 1
    fi
}

# obtener la ip de esta maquina
get_ip() {
    IP=$(hostname -I | awk '{print $1}')
    echo -e "${YELLOW}ip detectada: ${IP}${NC}"
}

# verificar si ya hay ip estatica, si no la hay pedir los datos
check_static_ip() {
    echo -e "${YELLOW}revisando ip estatica...${NC}"

    IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    STATIC=$(grep -r "addresses:" /etc/netplan/ 2>/dev/null)

    if [[ -z "$STATIC" ]]; then
        echo -e "${RED}no hay ip estatica configurada${NC}"
        echo -e "${YELLOW}hay que configurar una antes de continuar${NC}"

        read -p "ip estatica (ejemplo 192.168.1.100): " STATIC_IP
        read -p "prefijo de mascara (ejemplo 24): " PREFIX
        read -p "puerta de enlace (ejemplo 192.168.1.1): " GATEWAY
        read -p "dns a usar (ejemplo 8.8.8.8): " DNS_PRIMARY

        # crear el archivo de configuracion de netplan
        cat <<EOF > /etc/netplan/01-static.yaml
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: no
      addresses:
        - ${STATIC_IP}/${PREFIX}
      gateway4: ${GATEWAY}
      nameservers:
        addresses: [${DNS_PRIMARY}]
EOF
        netplan apply
        IP=$STATIC_IP
        echo -e "${GREEN}listo, ip $STATIC_IP configurada${NC}"
    else
        echo -e "${GREEN}ya tiene ip estatica, continuando...${NC}"
        get_ip
    fi
}

# instalar bind9 solo si no esta corriendo todavia
install_bind9() {
    echo -e "${YELLOW}checando si bind9 ya esta instalado...${NC}"

    if systemctl is-active --quiet bind9; then
        echo -e "${GREEN}bind9 ya esta corriendo, me lo salto${NC}"
    else
        echo -e "${YELLOW}instalando bind9...${NC}"
        apt-get update -y
        apt-get install -y bind9 bind9utils bind9-doc
        echo -e "${GREEN}bind9 instalado${NC}"
    fi
}

# agregar la zona al archivo named.conf.local
configure_zone() {
    echo -e "${YELLOW}configurando zona $DOMAIN...${NC}"

    # si ya existe la zona no la agrego dos veces
    if grep -q "zone \"${DOMAIN}\"" ${NAMED_LOCAL} 2>/dev/null; then
        echo -e "${GREEN}la zona ya estaba, me la salto${NC}"
    else
        cat <<EOF >> ${NAMED_LOCAL}

zone "${DOMAIN}" {
    type master;
    file "${ZONE_FILE}";
};
EOF
        echo -e "${GREEN}zona agregada${NC}"
    fi
}

# crear el archivo de zona con los registros A y CNAME
create_zone_file() {
    echo -e "${YELLOW}creando archivo de zona...${NC}"

    # si ya existe tampoco lo sobreescribo
    if [[ -f "$ZONE_FILE" ]]; then
        echo -e "${GREEN}el archivo ya existe, me lo salto${NC}"
        return
    fi

    cat <<EOF > ${ZONE_FILE}
\$TTL    604800
@   IN  SOA ns1.${DOMAIN}. admin.${DOMAIN}. (
            2024010101  ; serial
            604800      ; refresh
            86400       ; retry
            2419200     ; expire
            604800 )    ; cache negativo

@       IN  NS  ns1.${DOMAIN}.
ns1     IN  A   ${IP}

; registro A para el dominio principal
@       IN  A   ${IP}

; www apunta al mismo dominio con CNAME
www     IN  CNAME   ${DOMAIN}.
EOF

    echo -e "${GREEN}archivo de zona creado en $ZONE_FILE${NC}"
}

# validar que no haya errores de sintaxis y reiniciar bind9
validate_and_restart() {
    echo -e "${YELLOW}validando sintaxis con named-checkconf...${NC}"
    named-checkconf

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}sintaxis ok${NC}"
    else
        echo -e "${RED}hay errores, revisa los archivos de configuracion${NC}"
        exit 1
    fi

    systemctl restart bind9
    systemctl enable bind9
    echo -e "${GREEN}bind9 reiniciado${NC}"
}

# correr las pruebas para ver si resuelve bien
run_tests() {
    echo -e "${YELLOW}probando resolucion DNS...${NC}"

    echo ""
    echo -e "${YELLOW}nslookup reprobados.com${NC}"
    nslookup ${DOMAIN} 127.0.0.1

    echo ""
    echo -e "${YELLOW}nslookup www.reprobados.com${NC}"
    nslookup www.${DOMAIN} 127.0.0.1

    echo ""
    echo -e "${YELLOW}ping www.reprobados.com${NC}"
    ping -c 4 www.${DOMAIN}
}

# --- inicio del script ---
echo "====================================="
echo " DNS setup - $DOMAIN"
echo "====================================="
echo ""

check_root
check_static_ip
install_bind9
configure_zone
create_zone_file
validate_and_restart
run_tests

echo ""
echo -e "${GREEN}todo listo${NC}"