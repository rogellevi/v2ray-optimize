#!/bin/bash

# ============================================
# Script de Optimización V2Ray + BBR
# Para: v2ray.cloudgt.xyz
# ============================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para mostrar progreso
show_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

show_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

show_error() {
    echo -e "${RED}[✗]${NC} $1"
}

show_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Verificar si es root
if [[ $EUID -ne 0 ]]; then
   show_error "Este script debe ejecutarse como root (sudo)"
   exit 1
fi

clear
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════╗"
echo "║   Optimización V2Ray + BBR Automática    ║"
echo "║         v2ray.cloudgt.xyz                ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================
# 1. Verificar sistema
# ============================================
show_status "Verificando sistema..."

# Detectar OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
else
    OS=$(uname -s)
fi

show_success "Sistema detectado: $OS"

# Verificar kernel
KERNEL=$(uname -r)
show_status "Kernel actual: $KERNEL"

KERNEL_MAJOR=$(echo $KERNEL | cut -d. -f1)
KERNEL_MINOR=$(echo $KERNEL | cut -d. -f2)

if [ "$KERNEL_MAJOR" -lt 4 ] || ([ "$KERNEL_MAJOR" -eq 4 ] && [ "$KERNEL_MINOR" -lt 9 ]); then
    show_warning "Kernel antiguo detectado (necesitas 4.9+ para BBR)"
    echo -n "¿Actualizar kernel? (s/N): "
    read -r update_kernel
    if [[ $update_kernel =~ ^[Ss]$ ]]; then
        show_status "Actualizando kernel..."
        if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
            apt-get update -y
            apt-get upgrade -y
            apt-get install -y linux-generic
            show_warning "Reinicia el servidor después de la actualización"
        elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
            yum update -y
            yum install -y kernel
            show_warning "Reinicia el servidor después de la actualización"
        fi
    else
        show_error "BBR requiere kernel 4.9+. Saliendo..."
        exit 1
    fi
fi

# ============================================
# 2. Backup de configuración actual
# ============================================
show_status "Creando backup de sysctl.conf..."
cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S)
show_success "Backup creado"

# ============================================
# 3. Activar BBR
# ============================================
show_status "Activando BBR..."

# Cargar módulo BBR
if modprobe tcp_bbr 2>/dev/null; then
    show_success "Módulo BBR cargado"
else
    show_error "No se puede cargar BBR. ¿Kernel compatible?"
    echo -n "¿Continuar de todos modos? (s/N): "
    read -r continue_anyway
    if [[ ! $continue_anyway =~ ^[Ss]$ ]]; then
        exit 1
    fi
fi

# Configurar BBR
cat > /etc/sysctl.d/99-bbr-optimization.conf << 'EOF'
# ============================================
# Configuración BBR y Optimizaciones de Red
# ============================================

# BBR Congestion Control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP Fast Open (3 = activado para cliente y servidor)
net.ipv4.tcp_fastopen = 3

# Buffers optimizados para alto rendimiento
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# Optimizaciones de latencia
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_slow_start_after_idle = 0

# MTU probing (mejora conexiones con path MTU issues)
net.ipv4.tcp_mtu_probing = 1

# Reducir buffering para baja latencia
net.ipv4.tcp_notsent_lowat = 16384

# Optimizaciones de conexión
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10

# Keepalive optimizado
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# Seguridad básica
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# IPv6 optimizaciones
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0

# File descriptors máximos
fs.file-max = 1000000
EOF

# Aplicar configuración
sysctl -p /etc/sysctl.d/99-bbr-optimization.conf
sysctl -p /etc/sysctl.conf

show_success "BBR activado y configurado"

# ============================================
# 4. Verificar BBR
# ============================================
show_status "Verificando activación de BBR..."

CONGESTION=$(sysctl -n net.ipv4.tcp_congestion_control)
if [ "$CONGESTION" == "bbr" ]; then
    show_success "BBR activo: $CONGESTION"
else
    show_warning "Control de congestión actual: $CONGESTION"
fi

if lsmod | grep -q bbr; then
    show_success "Módulo BBR cargado en kernel"
else
    show_warning "Módulo BBR no detectado en kernel"
fi

# ============================================
# 5. Optimizar límites del sistema
# ============================================
show_status "Optimizando límites del sistema..."

cat > /etc/security/limits.d/99-v2ray.conf << EOF
* soft nofile 1000000
* hard nofile 1000000
* soft nproc 32768
* hard nproc 32768
root soft nofile 1000000
root hard nofile 1000000
EOF

show_success "Límites del sistema optimizados"

# ============================================
# 6. Detectar y reiniciar V2Ray
# ============================================
show_status "Buscando instalación de V2Ray..."

V2RAY_SERVICE=""

# Buscar diferentes nombres de servicio
if systemctl is-active --quiet v2ray; then
    V2RAY_SERVICE="v2ray"
elif systemctl is-active --quiet xray; then
    V2RAY_SERVICE="xray"
elif [ -f /etc/systemd/system/v2ray.service ]; then
    V2RAY_SERVICE="v2ray"
fi

if [ -n "$V2RAY_SERVICE" ]; then
    show_status "Reiniciando $V2RAY_SERVICE..."
    systemctl restart $V2RAY_SERVICE
    systemctl is-active --quiet $V2RAY_SERVICE && show_success "$V2RAY_SERVICE reiniciado correctamente" || show_error "Error al reiniciar $V2RAY_SERVICE"
else
    show_warning "No se detectó V2Ray como servicio systemd"
    echo -n "¿Reiniciar V2Ray manualmente? (s/N): "
    read -r restart_manual
    if [[ $restart_manual =~ ^[Ss]$ ]]; then
        pkill v2ray || pkill xray
        sleep 2
        show_status "V2Ray detenido. Inícialo manualmente."
    fi
fi

# ============================================
# 7. Verificación final
# ============================================
echo ""
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════╗"
echo "║       Optimización Completada             ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${BLUE}Resumen de optimizaciones:${NC}"
echo "  ✓ BBR activado"
echo "  ✓ TCP Fast Open activado"
echo "  ✓ Buffers optimizados"
echo "  ✓ Límites del sistema aumentados"
echo "  ✓ Configuraciones de baja latencia aplicadas"

echo ""
echo -e "${YELLOW}Comandos útiles para verificar:${NC}"
echo "  • Ver BBR: sysctl net.ipv4.tcp_congestion_control"
echo "  • Ver módulo: lsmod | grep bbr"
echo "  • Ver conexiones BBR: ss -ti | grep bbr"
echo "  • Ver V2Ray: systemctl status v2ray"
echo "  • Test velocidad: curl -o /dev/null http://speedtest.tele2.net/100MB.zip"

echo ""
echo -e "${GREEN}✓ ¡Servidor optimizado para baja latencia y estabilidad!${NC}"

# Preguntar si quiere reiniciar el servidor
echo ""
echo -n "¿Reiniciar el servidor ahora para asegurar todos los cambios? (s/N): "
read -r reboot_now
if [[ $reboot_now =~ ^[Ss]$ ]]; then
    show_warning "Reiniciando en 5 segundos..."
    sleep 5
    reboot
else
    show_status "Puedes reiniciar manualmente más tarde si es necesario."
fi