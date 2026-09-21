#!/usr/bin/env bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Скрипт должен запускаться от root
if [[ $EUID -ne 0 ]]; then
    error "Запусти скрипт от root или через sudo."
    exit 1
fi

log "Начинаем очистку системы..."

# 1. Очистка APT
if command -v apt-get >/dev/null 2>&1; then
    log "Очищаем кэш APT..."

    apt-get autoremove -y
    apt-get autoclean -y
    apt-get clean
else
    warn "APT не найден. Пропускаем очистку пакетов."
fi

# 2. Очистка systemd journal
if command -v journalctl >/dev/null 2>&1; then
    log "Очищаем старые логи systemd..."

    if journalctl --vacuum-size=200M; then
        log "Размер journal ограничен примерно 200 MB."
    else
        warn "Не удалось очистить journal."
    fi
else
    warn "journalctl не найден. Пропускаем очистку логов."
fi

# 3. Очистка Docker
if command -v docker >/dev/null 2>&1; then

    if systemctl is-active --quiet docker 2>/dev/null; then
        log "Очищаем неиспользуемые Docker-ресурсы..."

        if docker system prune -f; then
            log "Неиспользуемые Docker-контейнеры, сети и образы очищены."
        else
            warn "Не удалось выполнить очистку Docker."
        fi
    else
        warn "Docker установлен, но сейчас не запущен."
    fi
else
    log "Docker не установлен. Пропускаем очистку Docker."
fi

# 4. Очистка старых файлов в /tmp
if [[ -d /tmp ]]; then
    log "Удаляем файлы из /tmp, которые не использовались больше 7 дней..."

    find /tmp \
        -type f \
        -atime +7 \
        -delete \
        2>/dev/null || warn "При очистке /tmp возникли некоторые ошибки."
else
    warn "Директория /tmp не найдена."
fi

log "Очистка системы завершена."
