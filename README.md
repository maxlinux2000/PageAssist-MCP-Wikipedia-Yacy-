# Stack Local de Inteligencia Artificial (Page Assist + MCP + Kiwix + YaCy)

Este repositorio contiene un conjunto de scripts en Bash para desplegar un entorno de IA totalmente privado y local en Debian/Ubuntu.

## Componentes del Stack

1. **Ollama:** Hospeda los modelos LLM (`qwen3:30b-a3b`) y embeddings (`bge-m3`).
2. **Kiwix:** Servidor HTTP para la consulta offline de Wikipedia ZIM.
3. **Kiwix MCP Server:** Puente de comunicación HTTP-MCP para consultar Wikipedia desde el LLM.
4. **YaCy MCP Server:** Puente de comunicación HTTP-MCP para el motor de búsqueda P2P/Local YaCy.

## Requisitos Previos

- Sistema operativo basado en Debian/Ubuntu.
- Usuario con permisos `sudo`.

## Orden de Instalación

Ejecuta los scripts secuencialmente con tu usuario habitual (sin `sudo` inicial):

```bash
./1_instalar_stack_ollama.sh
./2_instalar_kiwix.sh
./3_instalar_kiwix_mcp.sh
./4_instalar_yacy_mcp.sh
```
Configuración en Page Assist

Añade los servidores MCP en la extensión de navegador Page Assist utilizando el transporte Streamable HTTP:

    YaCy Search: http://127.0.0.1:8091/mcp

    Kiwix Wikipedia: http://127.0.0.1:8081/mcp (o el puerto configurado en tu servidor Kiwix MCP)

