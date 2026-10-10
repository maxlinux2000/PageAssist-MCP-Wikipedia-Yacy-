#!/bin/bash

# =================================================================
# SCRIPT DE INSTALACIÓN: OLLAMA + MODELOS + FIREFOX (PAGE ASSIST)
# =================================================================

# --- 0. VERIFICACIÓN DE USUARIO ---
if [[ $EUID -eq 0 ]]; then
   echo "🚫 ERROR: ¡No ejecute este script como root (usando 'sudo')!"
   echo "Ejecútelo como su usuario normal. El script pedirá la contraseña de sudo cuando sea necesario."
   exit 1
fi

# --- CONFIGURACIÓN DE MODELOS Y RUTAS ---
MODELO_LLM="qwen3:30b-a3b"
MODELO_EMBEDDINGS="bge-m3"
OLLAMA_INSTALL_URL="https://ollama.com/install.sh"
PAGE_ASSIST_URL="https://addons.mozilla.org/es/firefox/addon/page-assist/"

echo "🚀 Iniciando la instalación del entorno Ollama + Modelos..."

# ----------------------------------------------------------------
# PASO 1: INSTALAR DEPENDENCIAS BASE (Debian)
# ----------------------------------------------------------------
instalar_base_debian() {
    echo "1/4: Actualizando repositorios e instalando dependencias (curl, firefox)..."
    
    sudo sed -i '/^deb / s/ main/ main contrib non-free/g' /etc/apt/sources.list 2>/dev/null || true
    sudo apt update -y
    sudo apt install -y curl firefox jq

    # Detección y preparación opcional de aceleración gráfica
    if lspci -k | grep -i vga | grep -i nvidia > /dev/null; then
        echo "ℹ️ GPU NVIDIA detectada. Asegurando controladores..."
        sudo apt install -y nvidia-driver nvidia-cuda-toolkit
    elif lspci -k | grep -i vga | grep -i intel > /dev/null; then
        sudo apt install -y intel-media-va-driver-non-free
    fi
}

# ----------------------------------------------------------------
# PASO 2: INSTALACIÓN DE OLLAMA Y CONFIGURACIÓN DE SYSTEMD
# ----------------------------------------------------------------
instalar_y_configurar_ollama() {
    echo "2/4: Instalando/Actualizando Ollama y configurando servicio..."
    
    # Descarga e instalación de Ollama mediante su script oficial
    curl -fsSL "$OLLAMA_INSTALL_URL" | sh

    # Asegurar el directorio de trabajo del servicio
    sudo mkdir -p /usr/share/ollama
    if id -u ollama >/dev/null 2>&1; then
        sudo chown -R ollama:ollama /usr/share/ollama
    fi

    # Reiniciar y habilitar el servicio systemd de Ollama
    sudo systemctl daemon-reload
    sudo systemctl enable ollama
    sudo systemctl restart ollama

    # Esperar a que el daemon esté escuchando en el puerto 11434
    echo "⌛ Esperando a que el servicio Ollama responda..."
    until curl -s http://127.0.0.1:11434/api/tags > /dev/null; do
        sleep 1
    done
    echo "✅ Servicio Ollama activo y respondiendo."
}

# ----------------------------------------------------------------
# PASO 3: DESCARGA DE MODELOS
# ----------------------------------------------------------------
descargar_modelos() {
    echo "3/4: Descargando modelos configurados..."

    echo "📦 Descargando modelo LLM principal: $MODELO_LLM..."
    ollama pull "$MODELO_LLM"

    echo "📦 Descargando modelo de Embeddings RAG: $MODELO_EMBEDDINGS..."
    ollama pull "$MODELO_EMBEDDINGS"

    echo "✅ Lista de modelos instalados en Ollama:"
    ollama list
}

# ----------------------------------------------------------------
# PASO 4: APERTURA DE FIREFOX Y NAVEGACIÓN A PAGE ASSIST
# ----------------------------------------------------------------
abrir_page_assist() {
    echo "4/4: Abriendo Firefox para instalar la extensión Page Assist..."
    
    if command -v firefox >/dev/null 2>&1; then
        nohup firefox "$PAGE_ASSIST_URL" >/dev/null 2>&1 &
        echo "✅ Firefox iniciado en la página de la extensión Page Assist."
    else
        echo "⚠️ Firefox no se encontró en el sistema. Puedes instalar Page Assist manualmente en:"
        echo "   $PAGE_ASSIST_URL"
    fi
}

# =================================================================
# EJECUCIÓN PRINCIPAL
# =================================================================
instalar_base_debian
instalar_y_configurar_ollama
descargar_modelos
abrir_page_assist

echo ""
echo "=========================================================="
echo "🥳 Instalación del stack Ollama finalizada con éxito."
echo "  - LLM: $MODELO_LLM"
echo "  - Embeddings: $MODELO_EMBEDDINGS"
echo "  - Extensión recomendada: Page Assist (Firefox)"
echo "=========================================================="

