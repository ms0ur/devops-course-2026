
#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"

    if [[ "$actual" == "$expected" ]]; then
        echo " [OK]   $desc"
        ((PASS++))
    else
        echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"

check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin /{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication /{print $2}')"

port="$(sudo sshd -T | awk '/^port /{print $2}')"
if [[ -n "$port" && "$port" != "22" ]]; then
    port_ok="yes"
else
    port_ok="no"
fi
check "SSH использует нестандартный порт" "yes" "$port_ok"

check "MaxAuthTries равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries /{print $2}')"

echo "[2] Межсетевой экран"

check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
check "Политика входящих соединений" "deny" "$(sudo ufw status verbose | sed -nE 's/^Default: ([a-z]+) \(incoming\).*/\1/p')"

echo "[3] Учётные записи"

awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd


echo "[4] Веб-сервер"

# 1. Служба Nginx активна
check "Служба Nginx активна" "active" "$(systemctl is-active nginx)"

# 2. Синтаксис конфигурации корректен
nginx_result=1
if sudo nginx -t >/dev/null 2>&1; then
    nginx_result=0
fi

check "Конфигурация Nginx корректна" "0" "$nginx_result"

# 3. Сертификат действителен ещё минимум 30 дней
CERT_CHECK_SECONDS="${CERT_CHECK_SECONDS:-2592000}"

cert_result=1
if openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend "$CERT_CHECK_SECONDS" >/dev/null 2>&1; then
    cert_result=0
fi

check "Сертификат действителен ещё 30 дней" "0" "$cert_result"

# 4. Нет world-writable файлов, закрытый ключ имеет права 600
writable_files="$(find /var/www/devops-site -perm -o+w -print -quit)"
key_mode="$(sudo stat -c '%a' /etc/ssl/private/devops.key)"

permissions_ok="no"
if [[ -z "$writable_files" && "$key_mode" == "600" ]]; then
    permissions_ok="yes"
fi

check "Права сайта и TLS-ключа безопасны" "yes" "$permissions_ok"


echo "Пройдено: $PASS, не пройдено: $FAIL"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
