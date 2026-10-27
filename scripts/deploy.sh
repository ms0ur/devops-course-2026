
#!/usr/bin/env bash
# Доставка статического сайта devops.local
# Использование: scripts/deploy.sh [--dry-run]

set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site"

DRY_RUN=false

if [[ $# -gt 1 ]]; then
    echo "Использование: $0 [--dry-run]" >&2
    exit 1
fi

if [[ $# -eq 1 ]]; then
    if [[ "$1" != "--dry-run" ]]; then
        echo "Неизвестный аргумент: $1" >&2
        exit 1
    fi
    DRY_RUN=true
fi

# Проверка главной страницы
if [[ ! -f "${LOCAL_DIR}/index.html" ]]; then
    echo "Ошибка: отсутствует site/index.html" >&2
    exit 1
fi

# Проверка чистоты репозитория, включая staged/untracked
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения" >&2
    exit 1
fi

RSYNC_ARGS=(-avz --delete --chmod=D755,F644)
SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5"

if [[ "$DRY_RUN" == true ]]; then
    RSYNC_ARGS+=(--dry-run)
    echo "Пробная доставка (без изменений на сервере)"
fi

echo "Источник: ${LOCAL_DIR}/"
echo "Назначение: ${REMOTE}:${REMOTE_DIR}/"

# Единственное новое SSH-соединение в рамках запуска
if ! rsync "${RSYNC_ARGS[@]}" -e "$SSH_COMMAND" "${LOCAL_DIR}/" "${REMOTE}:${REMOTE_DIR}/"; then
    echo "Ошибка: синхронизация не удалась" >&2
    exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
    echo "Пробный запуск завершён"
    exit 0
fi

if [[ ! -f "$CA_CERT" ]]; then
    echo "Ошибка: не найден сертификат $CA_CERT" >&2
    exit 1
fi

CURL_ARGS=(--fail --silent --show-error --noproxy '*' --max-time 10 --cacert "$CA_CERT")

# Необязательный маршрут для клиента за NAT
if [[ -n "${DEVOPS_CONNECT_TO:-}" ]]; then
    CURL_ARGS+=(--connect-to "$DEVOPS_CONNECT_TO")
fi

echo "Проверка HTTPS: ${SITE_URL}/"

if ! curl "${CURL_ARGS[@]}" -o /dev/null "${SITE_URL}/"; then
    echo "Ошибка: HTTPS-проверка не пройдена" >&2
    exit 1
fi

echo "Деплой выполнен успешно"
echo "Коммит: $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
