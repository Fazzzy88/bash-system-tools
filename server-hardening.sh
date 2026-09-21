#!/usr/bin/env bash

set -euo pipefail

NEW_USER="${NEW_USER:-adminuser}"
SSH_PORT="${SSH_PORT:-22}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

fail() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Скрипт должен запускаться от root
if [[ $EUID -ne 0 ]]; then
    fail "Запусти скрипт от root или через sudo."
fi

# Проверяем, что это Debian/Ubuntu
if [[ ! -f /etc/os-release ]]; then
    fail "Не удалось определить операционную систему."
fi

source /etc/os-release

if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
    fail "Этот скрипт рассчитан на Ubuntu или Debian."
fi

# Проверяем порт
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
    fail "Некорректный SSH-порт: $SSH_PORT"
fi

info "Начинаем настройку сервера..."

# Обновляем систему
info "Обновляем пакеты..."
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get upgrade -y

# Ставим необходимые пакеты
info "Устанавливаем необходимые пакеты..."

apt-get install -y \
    ufw \
    fail2ban \
    curl \
    git \
    tar \
    sudo \
    openssh-server

# Создаем пользователя
if id "$NEW_USER" >/dev/null 2>&1; then
    info "Пользователь '$NEW_USER' уже существует."
else
    info "Создаем пользователя '$NEW_USER'..."

    useradd -m -s /bin/bash "$NEW_USER"
    usermod -aG sudo "$NEW_USER"

    info "Пользователь '$NEW_USER' добавлен в группу sudo."
    warn "Пароль для '$NEW_USER' не установлен. Настрой SSH-ключ или пароль перед использованием."
fi

# Настраиваем SSH
SSH_CONFIG="/etc/ssh/sshd_config"

if [[ -f "$SSH_CONFIG" ]]; then
    info "Настраиваем SSH..."

    cp "$SSH_CONFIG" "${SSH_CONFIG}.bak"

    # Удаляем старые активные настройки Port
    sed -i '/^[[:space:]]*Port[[:space:]]/d' "$SSH_CONFIG"

    echo "Port $SSH_PORT" >> "$SSH_CONFIG"

    # Проверяем конфигурацию до перезапуска SSH
    if sshd -t; then
        systemctl restart ssh 2>/dev/null || systemctl restart sshd
    else
        warn "Ошибка в конфигурации SSH. Возвращаем предыдущий вариант."
        mv "${SSH_CONFIG}.bak" "$SSH_CONFIG"
        exit 1
    fi
fi

# Настраиваем firewall
info "Настраиваем UFW..."

ufw --force reset

ufw default deny incoming
ufw default allow outgoing

# Сначала разрешаем SSH, потом включаем firewall
ufw allow "${SSH_PORT}/tcp" comment "SSH"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"

ufw --force enable

# Настраиваем Fail2ban
info "Настраиваем Fail2ban..."

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = $SSH_PORT
EOF

# Проверяем конфигурацию Fail2ban
if ! fail2ban-client -t >/dev/null 2>&1; then
    fail "Ошибка в конфигурации Fail2ban."
fi

systemctl enable fail2ban
systemctl restart fail2ban

# Проверяем, что основные службы работают
info "Проверяем службы..."

if ! systemctl is-active --quiet fail2ban; then
    fail "Fail2ban не запущен."
fi

if ! systemctl is-active --quiet ssh 2>/dev/null && \
   ! systemctl is-active --quiet sshd 2>/dev/null; then
    fail "SSH не запущен."
fi

echo
info "Настройка завершена."
echo
echo "Пользователь: $NEW_USER"
echo "SSH порт:     $SSH_PORT"
echo "UFW:          включен"
echo "Fail2ban:     включен"
echo
warn "Не закрывай текущую SSH-сессию, пока не проверишь новое подключение."
