#!/bin/bash

# =================================================================
# SCRIPT DE INSTALACIÓN Y SERVICIO SYSTEMD PARA YACY MCP
# =================================================================

# --- 0. VERIFICACIÓN DE USUARIO ---
if [[ $EUID -eq 0 ]]; then
   echo "🚫 ERROR: ¡No ejecute este script como root (usando 'sudo')!"
   echo "Ejecútelo como su usuario normal. Pedirá la contraseña de sudo cuando sea necesario."
   exit 1
fi

TARGET_DIR="$HOME/.local/bin"
SCRIPT_STDIO="$TARGET_DIR/yacy-mcp.sh"
SCRIPT_HTTP="$TARGET_DIR/yacy-mcp-http.py"
SERVICE_NAME="yacy-mcp.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

echo "🚀 Iniciando la instalación de los scripts YaCy MCP en $TARGET_DIR..."

mkdir -p "$TARGET_DIR"

# ----------------------------------------------------------------
# PASO 1: CREAR CONECTOR STDIO (yacy-mcp.sh)
# ----------------------------------------------------------------
echo "1/4: Creando $SCRIPT_STDIO..."

cat << 'EOF' > "$SCRIPT_STDIO"
#!/bin/bash

# Función para enviar respuestas JSON-RPC 2.0 por STDOUT
send_json() {
  echo "$1"
}

# Bucle principal de escucha STDIN (Model Context Protocol via stdio)
while IFS= read -r line; do
  [ -z "$line" ] && continue

  # Extraer campos clave del mensaje JSON-RPC
  METHOD=$(echo "$line" | jq -r '.method // empty')
  ID=$(echo "$line" | jq -c '.id // null')

  # 1. Petición de Inicialización
  if [ "$METHOD" = "initialize" ]; then
    RESPONSE=$(jq -n --argjson id "$ID" '{
      jsonrpc: "2.0",
      id: $id,
      result: {
        protocolVersion: "2024-11-05",
        capabilities: {
          tools: {}
        },
        serverInfo: {
          name: "yacy-search-server",
          version: "1.0.0"
        }
      }
    }')
    send_json "$RESPONSE"

  # 2. Notificación de inicialización completada
  elif [ "$METHOD" = "notifications/initialized" ]; then
    continue

  # 3. Listado de Herramientas disponibles
  elif [ "$METHOD" = "tools/list" ]; then
    RESPONSE=$(jq -n --argjson id "$ID" '{
      jsonrpc: "2.0",
      id: $id,
      result: {
        tools: [
          {
            name: "buscar_yacy",
            description: "Busca información en el motor de búsqueda local YaCy.",
            inputSchema: {
              type: "object",
              properties: {
                consulta: {
                  type: "string",
                  description: "El término o frase a buscar en YaCy"
                },
                limite: {
                  type: "number",
                  description: "Número máximo de resultados (por defecto 5)"
                }
              },
              required: ["consulta"]
            }
          }
        ]
      }
    }')
    send_json "$RESPONSE"

  # 4. Ejecución de la herramienta (tools/call)
  elif [ "$METHOD" = "tools/call" ]; then
    TOOL_NAME=$(echo "$line" | jq -r '.params.name')

    if [ "$TOOL_NAME" = "buscar_yacy" ]; then
      QUERY=$(echo "$line" | jq -r '.params.arguments.consulta')
      LIMIT=$(echo "$line" | jq -r '.params.arguments.limite // 5')

      # Codificar URL para la consulta
      ENCODED_QUERY=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$QUERY" 2>/dev/null || echo "$QUERY" | sed 's/ /+/g')

      # Consulta a la API de YaCy
      RAW_YACY=$(curl -s "http://127.0.0.1:8090/yacysearch.json?query=${ENCODED_QUERY}&maximumRecords=${LIMIT}&resource=local")

      # Python se encarga de parsear el JSON, decodificar HTML y reparar mojibake respetando Unicode
      FORMATTED_RESULT=$(python3 -c '
import json, html, sys

try:
    data = json.load(sys.stdin)
    items = data.get("channels", [{}])[0].get("items", [])
    output = []
    
    for item in items:
        title = html.unescape(item.get("title", ""))
        link = item.get("link", "")
        desc = html.unescape(item.get("description", ""))
        
        # Reparar posible mojibake si venía en latin1/UTF-8 cruzado
        try:
            desc = desc.encode("latin1").decode("utf-8")
        except Exception:
            pass
            
        try:
            title = title.encode("latin1").decode("utf-8")
        except Exception:
            pass

        # Quitar etiquetas HTML residuales
        import re
        desc = re.sub(r"<[^>]*>", "", desc)

        output.append(f"Título: {title}\nEnlace: {link}\nResumen: {desc}\n---")
    
    print("\n".join(output))
except Exception as e:
    print("")
' <<< "$RAW_YACY")

      if [ -z "$FORMATTED_RESULT" ]; then
        FORMATTED_RESULT="No se encontraron resultados en YaCy para: $QUERY"
      fi

      RESPONSE=$(jq -n --argjson id "$ID" --arg text "$FORMATTED_RESULT" '{
        jsonrpc: "2.0",
        id: $id,
        result: {
          content: [
            {
              type: "text",
              text: $text
            }
          ]
        }
      }')
      send_json "$RESPONSE"
    fi
  fi

done
EOF

chmod +x "$SCRIPT_STDIO"

# ----------------------------------------------------------------
# PASO 2: CREAR SERVIDOR HTTP (yacy-mcp-http.py)
# ----------------------------------------------------------------
echo "2/4: Creando $SCRIPT_HTTP..."

cat << 'EOF' > "$SCRIPT_HTTP"
#!/usr/bin/env python3
import json
import urllib.parse
import urllib.request
import html
import re
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = 8091

def buscar_yacy(query, limit=5):
    try:
        encoded_query = urllib.parse.quote(query)
        url = f"http://127.0.0.1:8090/yacysearch.json?query={encoded_query}&maximumRecords={limit}&resource=local"
        
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode('utf-8'))
            
        items = data.get("channels", [{}])[0].get("items", [])
        if not items:
            return f"No se encontraron resultados en YaCy para: {query}"
            
        output = []
        for item in items:
            title = html.unescape(item.get("title", ""))
            link = item.get("link", "")
            desc = html.unescape(item.get("description", ""))
            
            # Arreglar mojibake en descripción y título
            try:
                desc = desc.encode("latin1").decode("utf-8")
            except Exception:
                pass
            try:
                title = title.encode("latin1").decode("utf-8")
            except Exception:
                pass
                
            desc = re.sub(r"<[^>]*>", "", desc)
            output.append(f"Título: {title}\nEnlace: {link}\nResumen: {desc}\n---")
            
        return "\n".join(output)
    except Exception as e:
        return f"Error consultando YaCy: {str(e)}"

class MCPHTTPHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        # Soporte CORS para la extensión del navegador
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        # Endpoint de salud/verificación
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(b"Servidor MCP YaCy HTTP activo")

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')
        
        try:
            req_data = json.loads(body)
            method = req_data.get("method")
            req_id = req_data.get("id")
            
            response_data = None

            if method == "initialize":
                response_data = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {"tools": {}},
                        "serverInfo": {"name": "yacy-search-server", "version": "1.0.0"}
                    }
                }
            elif method == "notifications/initialized":
                self.send_response(204)
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                return
            elif method == "tools/list":
                response_data = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "tools": [
                            {
                                "name": "buscar_yacy",
                                "description": "Busca información en el motor de búsqueda local YaCy.",
                                "inputSchema": {
                                    "type": "object",
                                    "properties": {
                                        "consulta": {
                                            "type": "string",
                                            "description": "El término o frase a buscar en YaCy"
                                        },
                                        "limite": {
                                            "type": "number",
                                            "description": "Número máximo de resultados (por defecto 5)"
                                        }
                                    },
                                    "required": ["consulta"]
                                }
                            }
                        ]
                    }
                }
            elif method == "tools/call":
                params = req_data.get("params", {})
                tool_name = params.get("name")
                
                if tool_name == "buscar_yacy":
                    args = params.get("arguments", {})
                    query = args.get("consulta", "")
                    limit = args.get("limite", 5)
                    
                    resultado = buscar_yacy(query, limit)
                    
                    response_data = {
                        "jsonrpc": "2.0",
                        "id": req_id,
                        "result": {
                            "content": [{"type": "text", "text": resultado}]
                        }
                    }

            if response_data:
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps(response_data).encode('utf-8'))
            else:
                self.send_response(400)
                self.end_headers()
                
        except Exception as e:
            self.send_response(500)
            self.end_headers()

if __name__ == '__main__':
    print(f"Iniciando Servidor MCP HTTP para YaCy en http://127.0.0.1:{PORT}/mcp")
    httpd = HTTPServer(('127.0.0.1', PORT), MCPHTTPHandler)
    httpd.serve_forever()
EOF

chmod +x "$SCRIPT_HTTP"

# ----------------------------------------------------------------
# PASO 3: LIBERAR PUERTO Y CREAR SERVICIO SYSTEMD
# ----------------------------------------------------------------
echo "3/4: Configurando el servicio systemd ($SERVICE_NAME)..."

# Detener ejecuciones manuales previas que puedan ocupar el puerto 8091
pkill -f "yacy-mcp-http.py" 2>/dev/null || true

sudo bash -c "cat << EOF > $SERVICE_FILE
[Unit]
Description=Servidor MCP HTTP para YaCy
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=/usr/bin/python3 $SCRIPT_HTTP
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF"

# ----------------------------------------------------------------
# PASO 4: RECARGAR Y ARRANCAR EL SERVICIO
# ----------------------------------------------------------------
echo "4/4: Recargando daemon e iniciando el servicio..."

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

echo ""
echo "=========================================================="
echo "🥳 Instalación completada con éxito."
echo " Archivos creados:"
echo "   - $SCRIPT_STDIO"
echo "   - $SCRIPT_HTTP"
echo ""
echo " Servicio systemd:"
echo "   - Estado: sudo systemctl status $SERVICE_NAME"
echo "   - URL para Page Assist: http://127.0.0.1:8091/mcp"
echo "=========================================================="

