#!/bin/sh
# =============================================================================
# AmneziaWG для Asuswrt-Merlin
# Файл: src/backend/_globals.sh
# Описание: Глобальные переменные и константы
# =============================================================================

# Основные пути
SCRIPT_DIR="/jffs/addons/amneziawg"
CONFIG_DIR="${SCRIPT_DIR}/config"
PEERS_DIR="${CONFIG_DIR}/peers"
LOG_DIR="${SCRIPT_DIR}/logs"
BIN_DIR="${SCRIPT_DIR}/bin"
LIB_DIR="${SCRIPT_DIR}/lib"

# Конфигурационные файлы
MAIN_CONFIG="${CONFIG_DIR}/amneziawg.conf"
INTERFACE_CONFIG="${CONFIG_DIR}/awg0.conf"
FIREWALL_RULES="${CONFIG_DIR}/firewall-rules.sh"
ROUTING_RULES="${CONFIG_DIR}/routing-rules.sh"

# Логи
MAIN_LOG="${LOG_DIR}/amneziawg.log"
ERROR_LOG="${LOG_DIR}/error.log"
DEBUG_LOG="${LOG_DIR}/debug.log"

# Бинарные файлы
AWG_BIN="${BIN_DIR}/awg"
AWG_QUICK_BIN="${BIN_DIR}/awg-quick"

# Системные переменные
INTERFACE_NAME="awg0"
MODULE_NAME="amneziawg"
LISTEN_PORT="51820"

# Параметры Amnezia
JC_VALUE="3"
JMIN_VALUE="50"
JMAX_VALUE="1000"
S1_VALUE="0"
S2_VALUE="0"
H1_VALUE="1"
H2_VALUE="2"
H3_VALUE="3"
H4_VALUE="4"

# Настройки логирования
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
MAX_LOG_SIZE="1048576"  # 1MB в байтах
LOG_ROTATION="5"  # Количество ротируемых логов

# Таймауты и интервалы
KEEPALIVE_INTERVAL="25"
CONNECTION_TIMEOUT="30"
RETRY_INTERVAL="5"
MAX_RETRIES="3"

# Сетевые настройки по умолчанию
DEFAULT_MTU="1420"
DEFAULT_TABLE="auto"
DEFAULT_DNS="1.1.1.1, 1.0.0.1"

# Флаги состояния
IS_RUNNING=0
IS_ENABLED=0
DEBUG_MODE=0

# Цвета для вывода (если терминал поддерживает)
if [ -t 1 ]; then
    COLOR_RED="\033[0;31m"
    COLOR_GREEN="\033[0;32m"
    COLOR_YELLOW="\033[0;33m"
    COLOR_BLUE="\033[0;34m"
    COLOR_RESET="\033[0m"
else
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_RESET=""
fi

# Версия скрипта
SCRIPT_VERSION="1.0.0"

# Экспорт переменных для использования в других скриптах
export SCRIPT_DIR CONFIG_DIR PEERS_DIR LOG_DIR BIN_DIR LIB_DIR
export MAIN_CONFIG INTERFACE_CONFIG FIREWALL_RULES ROUTING_RULES
export MAIN_LOG ERROR_LOG DEBUG_LOG
export AWG_BIN AWG_QUICK_BIN
export INTERFACE_NAME MODULE_NAME LISTEN_PORT
export JC_VALUE JMIN_VALUE JMAX_VALUE S1_VALUE S2_VALUE H1_VALUE H2_VALUE H3_VALUE H4_VALUE
export LOG_LEVEL MAX_LOG_SIZE LOG_ROTATION
export KEEPALIVE_INTERVAL CONNECTION_TIMEOUT RETRY_INTERVAL MAX_RETRIES
export DEFAULT_MTU DEFAULT_TABLE DEFAULT_DNS
export SCRIPT_VERSION
