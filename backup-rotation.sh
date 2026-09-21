#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR="${SOURCE_DIR:-/etc}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/custom}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
LOG_FILE="${LOG_FILE:-/var/log/backup-rotation.log}"

DATE=$(date +"%Y-%m-%d_%H-%M-%S")
ARCHIVE_NAME="backup_${DATE}.tar.gz"
ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"

log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"

    echo "$message"
    echo "$message" >> "$LOG_FILE"
}

# Проверяем исходную директорию
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "ERROR: Директория '$SOURCE_DIR' не существует." >&2
    exit 1
fi

# Проверяем количество дней
if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
    echo "ERROR: RETENTION_DAYS должен быть числом." >&2
    exit 1
fi

# Создаем необходимые директории
mkdir -p "$BACKUP_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

# Создаем файл лога, если его еще нет
touch "$LOG_FILE"

log_message "Начинаем создание резервной копии '$SOURCE_DIR'."
log_message "Архив: '$ARCHIVE_PATH'"

# Создаем архив
if tar -czf "$ARCHIVE_PATH" -C "$SOURCE_DIR" . 2>>"$LOG_FILE"; then
    log_message "Резервная копия успешно создана: $ARCHIVE_NAME"
else
    log_message "ERROR: Не удалось создать резервную копию."
    rm -f "$ARCHIVE_PATH"
    exit 1
fi

# Удаляем старые архивы
log_message "Удаляем бэкапы старше $RETENTION_DAYS дней..."

OLD_BACKUPS=$(find "$BACKUP_DIR" \
    -type f \
    -name "backup_*.tar.gz" \
    -mtime +"$RETENTION_DAYS" \
    -print)

if [[ -n "$OLD_BACKUPS" ]]; then
    while IFS= read -r backup; do
        if rm -f "$backup"; then
            log_message "Удален старый бэкап: $backup"
        else
            log_message "ERROR: Не удалось удалить: $backup"
        fi
    done <<< "$OLD_BACKUPS"
else
    log_message "Старых бэкапов для удаления нет."
fi

log_message "Резервное копирование завершено."
