#!/bin/bash
# =============================================================================
# install_entorno_IA.sh
# Instalación automatizada y asíncrona del entorno de IA (Ubuntu)
# Uso: ./install_entorno_IA.sh <IP_inicial> <IP_final>
# Ejemplo: ./install_entorno_IA.sh 192.168.1.1 192.168.1.30
#
# REQUISITO: IAEnv.yml debe estar en el mismo directorio que este
# script. Se copiará automáticamente a cada equipo remoto vía scp.
# =============================================================================

set -euo pipefail

# --- Colores ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Argumentos ---
if [ "$#" -ne 2 ]; then
    echo -e "${YELLOW}Uso: $0 <IP_inicial> <IP_final>${NC}"
    echo -e "Ejemplo: $0 192.168.1.1 192.168.1.30"
    exit 1
fi

IP_START="$1"
IP_END="$2"

# --- Verificar que el .yml existe junto al script ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YML_FILE="${SCRIPT_DIR}/IAEnv.yml"

if [ ! -f "$YML_FILE" ]; then
    echo -e "${RED}Error: no se encuentra '${YML_FILE}'.${NC}"
    echo -e "Asegúrate de que IAEnv.yml está en el mismo directorio que este script."
    exit 1
fi

# --- Credenciales SSH (una sola vez) ---
echo -e "${BLUE}Introduce las credenciales SSH para los equipos remotos:${NC}"
read -rp "  Usuario: " SSH_USER
read -rsp "  Contraseña: " SSH_PASS
echo ""

LOG_DIR="/tmp/install_ia_logs"
ERROR_LOG="${LOG_DIR}/errores.log"
mkdir -p "$LOG_DIR"
> "$ERROR_LOG"

# --- Extraer base de red y octetos ---
BASE_NET=$(echo "$IP_START" | cut -d'.' -f1-3)
START_OCT=$(echo "$IP_START" | cut -d'.' -f4)
END_OCT=$(echo "$IP_END" | cut -d'.' -f4)

if [ "$START_OCT" -gt "$END_OCT" ]; then
    echo -e "${RED}Error: La IP inicial debe ser menor o igual que la IP final.${NC}"
    exit 1
fi

# --- Verificar sshpass en el equipo del profesor ---
if ! command -v sshpass &>/dev/null; then
    echo -e "${YELLOW}[AVISO] sshpass no encontrado. Instalando en este equipo...${NC}"
    sudo apt-get install -y sshpass
fi

# =============================================================================
# Script remoto (se ejecuta en cada máquina alumno)
# El heredoc sin comillas expande ${SSH_PASS} y ${SSH_USER} desde el profesor.
# El resto de variables remotas van escapadas con \$.
# =============================================================================
read -r -d '' REMOTE_SCRIPT << REMOTE_EOF || true

set -e
export DEBIAN_FRONTEND=noninteractive
SUDO_PASS="${SSH_PASS}"
CONDA_USER="${SSH_USER}"
ANACONDA_INSTALLER="Miniconda3-latest-Linux-x86_64.sh"
ANACONDA_URL="https://repo.anaconda.com/miniconda/\${ANACONDA_INSTALLER}"
ANACONDA_DIR="\${HOME}/anaconda3"
ENV_NAME="IAEnv"
YML_PATH="\${HOME}/IAEnv.yml"

# --- Función sudo sin prompt ---
sudo_cmd() {
    echo "\${SUDO_PASS}" | sudo -S "\$@" 2>/dev/null
}

# --- Función: paquete apt instalado ---
apt_installed() {
    dpkg-query -W -f='\${Status}' "\$1" 2>/dev/null | grep -q "install ok installed"
}

ALREADY_INSTALLED=()

# =============================================================
# [1/6] Update y paquetes base
# =============================================================
echo "[1/6] Actualizando repositorios..."
sudo_cmd apt-get update -y -qq
sudo_cmd apt-get upgrade -y -qq

for PKG in openssh-server net-tools curl; do
    if apt_installed "\${PKG}"; then
        echo "  [YA INSTALADO] \${PKG}"
        ALREADY_INSTALLED+=("\${PKG}")
    else
        echo "  [INSTALANDO]   \${PKG}..."
        sudo_cmd apt-get install -y -qq "\${PKG}"
    fi
done

# =============================================================
# [2/6] Anaconda
# =============================================================
echo "[2/6] Comprobando Miniconda..."

if [ -f "\${ANACONDA_DIR}/bin/conda" ]; then
    echo "  [YA INSTALADO] Miniconda/Anaconda (\${ANACONDA_DIR})"
    ALREADY_INSTALLED+=("miniconda3")
else
    echo "  [DESCARGANDO]  Miniconda (~100 MB)..."
    curl -fsSL "\${ANACONDA_URL}" -o "/tmp/\${ANACONDA_INSTALLER}"
    echo "  [INSTALANDO]   Miniconda en modo silencioso..."
    bash "/tmp/\${ANACONDA_INSTALLER}" -b -p "\${ANACONDA_DIR}"
    rm -f "/tmp/\${ANACONDA_INSTALLER}"
    echo "  [OK] Miniconda instalado."
fi

# Asegurar PATH y conda disponible en esta sesión
export PATH="\${ANACONDA_DIR}/bin:\${PATH}"
eval "\$("\${ANACONDA_DIR}/bin/conda" shell.bash hook)"

# Añadir al .bashrc si no está ya
if ! grep -q "anaconda3/bin" "\${HOME}/.bashrc" 2>/dev/null; then
    echo "export PATH=\${ANACONDA_DIR}/bin:\\\${PATH}" >> "\${HOME}/.bashrc"
fi

# =============================================================
# [3/6] conda init + solver rápido (libmamba)
# =============================================================
echo "[3/6] Inicializando conda y configurando solver rápido..."
"\${ANACONDA_DIR}/bin/conda" init bash --quiet

# Instalar libmamba solver si no está ya (acelera enormemente la resolución
# de dependencias al crear el entorno)
if "\${ANACONDA_DIR}/bin/conda" list -n base | grep -q "conda-libmamba-solver"; then
    echo "  [YA INSTALADO] conda-libmamba-solver"
else
    echo "  [INSTALANDO]   conda-libmamba-solver (solver rápido)..."
    "\${ANACONDA_DIR}/bin/conda" install -n base conda-libmamba-solver -y -q
fi
"\${ANACONDA_DIR}/bin/conda" config --set solver libmamba
echo "  [OK] Solver libmamba activado."

# =============================================================
# [4/6] Entorno conda IAEnv
# =============================================================
echo "[4/6] Comprobando entorno conda '\${ENV_NAME}'..."

if "\${ANACONDA_DIR}/bin/conda" env list | grep -q "^\${ENV_NAME}"; then
    echo "  [YA INSTALADO] Entorno conda '\${ENV_NAME}'"
    ALREADY_INSTALLED+=("\${ENV_NAME}")
else
    echo "  [CREANDO]      Entorno conda desde \${YML_PATH} (puede tardar 10-20 min)..."
    "\${ANACONDA_DIR}/bin/conda" env create --name "\${ENV_NAME}" --file="\${YML_PATH}" -q
    echo "  [OK] Entorno '\${ENV_NAME}' creado."
fi

# =============================================================
# [5/6] Jupyter Notebook
# =============================================================
echo "[5/6] Configurando Jupyter Notebook..."
JUPYTER_CFG="\${HOME}/.jupyter/jupyter_notebook_config.py"

if [ -f "\${JUPYTER_CFG}" ] && grep -q "notebook_dir" "\${JUPYTER_CFG}" 2>/dev/null; then
    echo "  [YA CONFIGURADO] Jupyter Notebook"
    ALREADY_INSTALLED+=("jupyter-config")
else
    mkdir -p "\${HOME}/.jupyter"
    echo "c.NotebookApp.notebook_dir = '\${HOME}'" > "\${JUPYTER_CFG}"
    echo "  [OK] Jupyter configurado con directorio raíz: \${HOME}"
fi

# =============================================================
# [6/6] anaconda-navigator
# =============================================================
echo "[6/6] Comprobando anaconda-navigator..."

if "\${ANACONDA_DIR}/bin/conda" run -n base anaconda-navigator --version &>/dev/null; then
    echo "  [YA INSTALADO] anaconda-navigator"
    ALREADY_INSTALLED+=("anaconda-navigator")
else
    echo "  [INSTALANDO]   anaconda-navigator..."
    "\${ANACONDA_DIR}/bin/conda" install -n base anaconda-navigator -y -q
    echo "  [OK] anaconda-navigator instalado."
fi

# =============================================================
# Resumen
# =============================================================
if [ "\${#ALREADY_INSTALLED[@]}" -gt 0 ]; then
    echo "[RESUMEN] Software ya instalado previamente: \${ALREADY_INSTALLED[*]}"
fi

echo "[OK] Instalación completada."
REMOTE_EOF

# =============================================================================
# Función de instalación para un único host
# =============================================================================
install_on_host() {
    local IP="$1"
    local LOG="${LOG_DIR}/install_${IP//./_}.log"
    local START_TIME
    START_TIME=$(date +%s)

    # Copiar el .yml al equipo remoto
    sshpass -p "$SSH_PASS" scp \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=15 \
        "$YML_FILE" \
        "${SSH_USER}@${IP}:~/IAEnv.yml" >> "$LOG" 2>&1 || true

    # Ejecutar el script remoto
    local EXIT_CODE=0
    sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=15 \
        -o ServerAliveInterval=60 \
        -o ServerAliveCountMax=30 \
        -o BatchMode=no \
        "$SSH_USER@$IP" \
        "bash -s" <<< "$REMOTE_SCRIPT" >> "$LOG" 2>&1 || EXIT_CODE=$?

    local END_TIME
    END_TIME=$(date +%s)
    local ELAPSED=$(( END_TIME - START_TIME ))

    if [ "$EXIT_CODE" -eq 0 ]; then
        echo -e "${GREEN}✔ [$(date '+%H:%M:%S')] El equipo con IP ${IP} ha terminado correctamente (${ELAPSED}s).${NC}"
        local PREV
        PREV=$(grep "\[YA INSTALAD" "$LOG" | sed 's/.*\[YA INSTALAD[AO]\] //' | tr '\n' ', ' | sed 's/, $//')
        if [ -n "$PREV" ]; then
            echo -e "${YELLOW}  ℹ ${IP}: ya estaba instalado → ${PREV}${NC}"
        fi
    else
        echo -e "${RED}✘ [$(date '+%H:%M:%S')] El equipo con IP ${IP} ha fallado (código $EXIT_CODE, ${ELAPSED}s).${NC}"
        {
            echo "======================================================"
            echo "  EQUIPO: ${IP}  |  Código de salida: ${EXIT_CODE}  |  $(date '+%Y-%m-%d %H:%M:%S')"
            echo "======================================================"
            cat "$LOG"
            echo ""
        } >> "$ERROR_LOG"
    fi
}

# =============================================================================
# Bucle principal
# =============================================================================
TOTAL=$(( END_OCT - START_OCT + 1 ))

echo -e "${BLUE}"
echo "======================================================"
echo "  Instalación masiva del entorno IA"
echo "  Rango: ${IP_START} → ${IP_END}  (${TOTAL} equipos)"
echo "  Usuario SSH: ${SSH_USER}"
echo "  Logs: ${LOG_DIR}/"
echo "  AVISO: Miniconda (~100 MB) + entorno conda con solver"
echo "  libmamba. Tiempo estimado: 10-20 min por equipo."
echo "======================================================"
echo -e "${NC}"

declare -A JOB_PIDS

for OCT in $(seq "$START_OCT" "$END_OCT"); do
    IP="${BASE_NET}.${OCT}"
    echo -e "${BLUE}▶ Lanzando instalación en ${IP}...${NC}"
    install_on_host "$IP" &
    JOB_PIDS["$IP"]=$!
    sleep 0.5
done

echo ""
echo -e "${YELLOW}⏳ Esperando a que terminen los ${TOTAL} equipos...${NC}"
echo ""

FAILED=0
for IP in "${!JOB_PIDS[@]}"; do
    wait "${JOB_PIDS[$IP]}" || (( FAILED++ )) || true
done

echo ""
echo -e "${BLUE}======================================================"
if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}  ✔ Todos los equipos completaron la instalación con éxito.${NC}"
else
    echo -e "${RED}  ✘ ${FAILED} equipo(s) fallaron. Log consolidado de errores:${NC}"
    echo -e "${RED}     ${ERROR_LOG}${NC}"
fi
echo -e "${BLUE}======================================================${NC}"
