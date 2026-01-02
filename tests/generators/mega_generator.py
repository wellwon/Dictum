#!/usr/bin/env python3
"""
Mega test generator - creates thousands of additional tests for TextSwitcher.
Goal: Reach 15,000+ tests with balanced should_convert ratio.
"""

import json
import os
from dataclasses import dataclass, asdict
from typing import List, Set, Tuple

# QWERTY to ЙЦУКЕН mapping
QWERTY_TO_RUSSIAN = {
    'q': 'й', 'w': 'ц', 'e': 'у', 'r': 'к', 't': 'е', 'y': 'н', 'u': 'г', 'i': 'ш', 'o': 'щ', 'p': 'з',
    '[': 'х', ']': 'ъ', 'a': 'ф', 's': 'ы', 'd': 'в', 'f': 'а', 'g': 'п', 'h': 'р', 'j': 'о', 'k': 'л',
    'l': 'д', ';': 'ж', "'": 'э', 'z': 'я', 'x': 'ч', 'c': 'с', 'v': 'м', 'b': 'и', 'n': 'т', 'm': 'ь',
    ',': 'б', '.': 'ю', '/': '.', '`': 'ё', '{': 'Х', '}': 'Ъ', ':': 'Ж', '"': 'Э', '<': 'Б', '>': 'Ю',
    '?': ',', '~': 'Ё',
    'Q': 'Й', 'W': 'Ц', 'E': 'У', 'R': 'К', 'T': 'Е', 'Y': 'Н', 'U': 'Г', 'I': 'Ш', 'O': 'Щ', 'P': 'З',
    'A': 'Ф', 'S': 'Ы', 'D': 'В', 'F': 'А', 'G': 'П', 'H': 'Р', 'J': 'О', 'K': 'Л', 'L': 'Д',
    'Z': 'Я', 'X': 'Ч', 'C': 'С', 'V': 'М', 'B': 'И', 'N': 'Т', 'M': 'Ь'
}

RUSSIAN_TO_QWERTY = {v: k for k, v in QWERTY_TO_RUSSIAN.items()}

@dataclass
class TestCase:
    id: str
    category: str
    input: str
    expected: str
    should_convert: bool
    notes: str = ""

def convert_en_to_ru(text: str) -> str:
    return ''.join(QWERTY_TO_RUSSIAN.get(c, c) for c in text)

def convert_ru_to_en(text: str) -> str:
    return ''.join(RUSSIAN_TO_QWERTY.get(c, c) for c in text)

# ============================================================================
# TECH COMPANIES & SERVICES (NO CONVERT - valid English)
# ============================================================================

TECH_GIANTS = [
    "Google", "Apple", "Microsoft", "Amazon", "Meta", "Netflix", "Tesla", "Nvidia",
    "Intel", "AMD", "IBM", "Oracle", "Salesforce", "Adobe", "Cisco", "Dell", "HP",
    "Lenovo", "Samsung", "Sony", "LG", "Huawei", "Xiaomi", "Alibaba", "Tencent",
    "Baidu", "ByteDance", "JD", "Meituan", "Pinduoduo", "Didi", "Uber", "Lyft",
    "Airbnb", "Booking", "Expedia", "TripAdvisor", "Yelp", "Zillow", "Redfin"
]

CLOUD_PROVIDERS = [
    "AWS", "Azure", "GCP", "DigitalOcean", "Linode", "Vultr", "Hetzner", "OVH",
    "Cloudflare", "Vercel", "Netlify", "Heroku", "Railway", "Render", "Fly",
    "Supabase", "PlanetScale", "Neon", "Turso", "CockroachDB", "MongoDB", "Redis",
    "Elasticsearch", "Kafka", "RabbitMQ", "Pulsar", "NATS", "Temporal", "Dagster"
]

DEV_TOOLS = [
    "GitHub", "GitLab", "Bitbucket", "Jira", "Confluence", "Notion", "Figma",
    "Sketch", "Miro", "Trello", "Asana", "Linear", "Slack", "Discord", "Zoom",
    "Teams", "Webex", "Meet", "Loom", "Calendly", "Typeform", "Airtable",
    "Coda", "Roam", "Obsidian", "Logseq", "Craft", "Bear", "Ulysses"
]

AI_SERVICES = [
    "OpenAI", "Anthropic", "Claude", "ChatGPT", "GPT", "Gemini", "Bard", "Copilot",
    "Midjourney", "DALL-E", "Stable Diffusion", "Runway", "ElevenLabs", "Whisper",
    "Replicate", "Hugging Face", "Cohere", "AI21", "Perplexity", "Jasper",
    "Copy.ai", "Writesonic", "Grammarly", "DeepL", "Otter", "Descript"
]

DATABASES = [
    "PostgreSQL", "MySQL", "MariaDB", "SQLite", "Oracle", "SQL Server", "DB2",
    "MongoDB", "CouchDB", "DynamoDB", "Cassandra", "ScyllaDB", "Redis", "Memcached",
    "Elasticsearch", "Solr", "Meilisearch", "Typesense", "Algolia", "Pinecone",
    "Weaviate", "Qdrant", "Milvus", "ChromaDB", "Neo4j", "ArangoDB", "TigerGraph"
]

FRAMEWORKS = [
    "React", "Vue", "Angular", "Svelte", "Next.js", "Nuxt", "Remix", "Astro",
    "SolidJS", "Qwik", "Preact", "Alpine", "HTMX", "Stimulus", "Turbo",
    "Rails", "Django", "Flask", "FastAPI", "Express", "NestJS", "Fastify",
    "Hono", "Elysia", "Spring", "Quarkus", "Micronaut", "Ktor", "Actix",
    "Axum", "Rocket", "Gin", "Echo", "Fiber", "Chi", "Phoenix", "Elixir"
]

RUSSIAN_SERVICES = [
    "Yandex", "VK", "Mail.ru", "Ozon", "Wildberries", "Avito", "HeadHunter",
    "Tinkoff", "Sber", "Alfa", "VTB", "Raiffeisen", "Gazprom", "Rosneft",
    "Lamoda", "Leroy Merlin", "DNS", "MVideo", "Eldorado", "Citilink",
    "Kaspersky", "ABBYY", "JetBrains", "Acronis", "Veeam", "DataArt"
]

CRYPTO_SERVICES = [
    "Bitcoin", "Ethereum", "Solana", "Polygon", "Avalanche", "Cardano", "Polkadot",
    "Cosmos", "Near", "Aptos", "Sui", "Arbitrum", "Optimism", "zkSync", "StarkNet",
    "Binance", "Coinbase", "Kraken", "FTX", "Gemini", "Crypto.com", "Uniswap",
    "Aave", "Compound", "MakerDAO", "Lido", "Rocket Pool", "OpenSea", "Blur"
]

SOCIAL_MEDIA = [
    "Twitter", "X", "Instagram", "TikTok", "YouTube", "LinkedIn", "Pinterest",
    "Reddit", "Snapchat", "Telegram", "WhatsApp", "Signal", "Mastodon", "Threads",
    "BeReal", "Clubhouse", "Discord", "Twitch", "Kick", "Rumble", "Odysee"
]

GAMING = [
    "Steam", "Epic Games", "Unity", "Unreal", "Godot", "Roblox", "Minecraft",
    "Fortnite", "Valorant", "League of Legends", "Dota", "Counter-Strike",
    "PlayStation", "Xbox", "Nintendo", "Ubisoft", "EA", "Activision", "Blizzard",
    "Riot", "Rockstar", "CD Projekt", "FromSoftware", "Capcom", "Konami", "Sega"
]

# ============================================================================
# CLI COMMANDS (NO CONVERT - system commands)
# ============================================================================

GIT_COMMANDS = [
    "git init", "git clone", "git add", "git commit", "git push", "git pull",
    "git fetch", "git merge", "git rebase", "git checkout", "git branch",
    "git status", "git log", "git diff", "git stash", "git reset", "git revert",
    "git cherry-pick", "git bisect", "git blame", "git show", "git tag",
    "git remote", "git submodule", "git worktree", "git reflog", "git gc"
]

NPM_COMMANDS = [
    "npm init", "npm install", "npm uninstall", "npm update", "npm run",
    "npm start", "npm test", "npm build", "npm publish", "npm link",
    "npm outdated", "npm audit", "npm cache", "npm config", "npm ls",
    "npx create-react-app", "npx vite", "npx next", "npx prisma"
]

YARN_COMMANDS = [
    "yarn init", "yarn add", "yarn remove", "yarn upgrade", "yarn run",
    "yarn start", "yarn test", "yarn build", "yarn publish", "yarn link",
    "yarn workspace", "yarn workspaces", "yarn dlx", "yarn dedupe"
]

PNPM_COMMANDS = [
    "pnpm init", "pnpm add", "pnpm remove", "pnpm update", "pnpm run",
    "pnpm install", "pnpm dlx", "pnpm exec", "pnpm store", "pnpm fetch"
]

DOCKER_COMMANDS = [
    "docker build", "docker run", "docker exec", "docker ps", "docker images",
    "docker pull", "docker push", "docker stop", "docker rm", "docker rmi",
    "docker logs", "docker inspect", "docker network", "docker volume",
    "docker compose up", "docker compose down", "docker compose build",
    "docker compose logs", "docker compose exec", "docker compose ps"
]

KUBECTL_COMMANDS = [
    "kubectl get", "kubectl describe", "kubectl apply", "kubectl delete",
    "kubectl create", "kubectl edit", "kubectl logs", "kubectl exec",
    "kubectl port-forward", "kubectl scale", "kubectl rollout", "kubectl config",
    "kubectl cluster-info", "kubectl top", "kubectl patch", "kubectl label"
]

SYSTEM_COMMANDS = [
    "ls -la", "cd ..", "mkdir -p", "rm -rf", "cp -r", "mv", "cat", "grep",
    "find . -name", "chmod +x", "chown", "sudo", "apt install", "brew install",
    "curl -O", "wget", "tar -xzf", "unzip", "ssh", "scp", "rsync", "ps aux",
    "kill -9", "top", "htop", "df -h", "du -sh", "free -m", "uname -a"
]

PYTHON_COMMANDS = [
    "python -m venv", "pip install", "pip freeze", "pip uninstall",
    "pytest", "pytest -v", "pytest --cov", "mypy", "ruff", "black",
    "isort", "flake8", "pylint", "poetry install", "poetry add", "poetry run",
    "uvicorn main:app", "gunicorn", "celery worker", "django-admin"
]

RUST_COMMANDS = [
    "cargo new", "cargo init", "cargo build", "cargo run", "cargo test",
    "cargo check", "cargo clippy", "cargo fmt", "cargo doc", "cargo publish",
    "cargo add", "cargo update", "rustup update", "rustup default"
]

GO_COMMANDS = [
    "go mod init", "go mod tidy", "go build", "go run", "go test",
    "go get", "go install", "go fmt", "go vet", "go generate"
]

# ============================================================================
# PROGRAMMING IDENTIFIERS (NO CONVERT - camelCase, snake_case)
# ============================================================================

COMMON_IDENTIFIERS = [
    # camelCase
    "getUserById", "setUserName", "getAuthToken", "validateInput", "parseJSON",
    "handleClick", "fetchData", "renderComponent", "updateState", "formatDate",
    "calculateTotal", "processOrder", "sendRequest", "handleError", "logMessage",
    "createUser", "deleteItem", "saveChanges", "loadConfig", "initApp",
    "checkPermission", "validateEmail", "hashPassword", "generateToken", "decodeJWT",
    "encryptData", "decryptMessage", "compressFile", "extractArchive", "uploadFile",
    # snake_case
    "get_user_by_id", "set_user_name", "get_auth_token", "validate_input", "parse_json",
    "handle_click", "fetch_data", "render_component", "update_state", "format_date",
    "calculate_total", "process_order", "send_request", "handle_error", "log_message",
    "create_user", "delete_item", "save_changes", "load_config", "init_app",
    "check_permission", "validate_email", "hash_password", "generate_token", "decode_jwt",
    # SCREAMING_SNAKE_CASE
    "MAX_RETRIES", "DEFAULT_TIMEOUT", "API_BASE_URL", "DATABASE_URL", "SECRET_KEY",
    "ACCESS_TOKEN", "REFRESH_TOKEN", "REDIS_HOST", "CACHE_TTL", "LOG_LEVEL",
    # PascalCase
    "UserService", "AuthController", "DatabaseManager", "ConfigLoader", "EventEmitter",
    "HttpClient", "WebSocketServer", "FileHandler", "CacheManager", "QueueProcessor"
]

FILE_NAMES = [
    ".gitignore", ".env", ".env.local", ".env.production", ".eslintrc",
    ".prettierrc", ".editorconfig", ".dockerignore", ".nvmrc", ".npmrc",
    "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
    "tsconfig.json", "vite.config.ts", "next.config.js", "webpack.config.js",
    "tailwind.config.js", "postcss.config.js", "jest.config.js", "vitest.config.ts",
    "Dockerfile", "docker-compose.yml", "Makefile", "README.md", "LICENSE",
    "CHANGELOG.md", "CONTRIBUTING.md", "Cargo.toml", "go.mod", "requirements.txt",
    "pyproject.toml", "setup.py", "Gemfile", "Rakefile", "build.gradle", "pom.xml"
]

# ============================================================================
# VALID ENGLISH SENTENCES (stress tests - NO CONVERT)
# ============================================================================

VALID_ENGLISH_SENTENCES = [
    "The quick brown fox jumps over the lazy dog",
    "Hello world this is a test",
    "React is a JavaScript library for building user interfaces",
    "Python is a programming language",
    "Machine learning models require training data",
    "Cloud computing enables scalable infrastructure",
    "DevOps practices improve deployment frequency",
    "Microservices architecture provides flexibility",
    "Continuous integration automates testing",
    "Version control tracks code changes",
    "API endpoints handle HTTP requests",
    "Database queries return filtered results",
    "Authentication tokens expire after timeout",
    "Cache invalidation improves performance",
    "Load balancing distributes traffic",
    "Docker containers package applications",
    "Kubernetes orchestrates container deployments",
    "GraphQL queries fetch specific data",
    "REST APIs use HTTP methods",
    "WebSocket connections enable real-time updates",
    "TypeScript adds static typing to JavaScript",
    "Rust provides memory safety guarantees",
    "Go enables concurrent programming",
    "Swift powers iOS applications",
    "Kotlin modernizes Android development",
    "Flutter creates cross-platform apps",
    "React Native builds mobile apps",
    "Electron packages desktop applications",
    "Node.js runs JavaScript on servers",
    "Deno provides secure runtime environment",
    "Bun offers fast JavaScript runtime",
    "PostgreSQL stores relational data",
    "MongoDB handles document storage",
    "Redis provides in-memory caching",
    "Elasticsearch enables full-text search",
    "Kafka processes event streams",
    "RabbitMQ manages message queues",
    "Terraform provisions infrastructure",
    "Ansible automates configuration",
    "Jenkins builds continuous pipelines",
    "GitHub Actions runs CI workflows",
]

# ============================================================================
# RUSSIAN WORDS TO CORRUPT (should convert)
# ============================================================================

RUSSIAN_COMMON_WORDS = [
    "привет", "пока", "спасибо", "пожалуйста", "извините", "простите",
    "здравствуйте", "досвидания", "хорошо", "плохо", "большой", "маленький",
    "красивый", "умный", "быстрый", "медленный", "новый", "старый",
    "работа", "дом", "машина", "телефон", "компьютер", "интернет",
    "программа", "файл", "папка", "код", "функция", "переменная",
    "сообщение", "письмо", "документ", "проект", "задача", "ошибка",
    "помощь", "вопрос", "ответ", "решение", "проблема", "результат",
    "время", "день", "неделя", "месяц", "год", "сегодня", "завтра", "вчера",
    "утро", "вечер", "ночь", "минута", "час", "секунда",
    "человек", "друг", "коллега", "клиент", "пользователь", "администратор",
    "директор", "менеджер", "разработчик", "программист", "дизайнер", "аналитик",
    "сервер", "база", "данные", "запрос", "ответ", "сессия", "токен",
    "страница", "кнопка", "форма", "поле", "таблица", "список", "меню",
    "настройки", "параметры", "опции", "фильтр", "поиск", "сортировка",
    "добавить", "удалить", "изменить", "сохранить", "отменить", "применить",
    "открыть", "закрыть", "загрузить", "скачать", "отправить", "получить",
    "создать", "копировать", "вставить", "вырезать", "выбрать", "найти",
    "проверить", "тестировать", "отладить", "исправить", "обновить", "установить",
    "запустить", "остановить", "перезапустить", "включить", "выключить",
]

RUSSIAN_IT_PHRASES = [
    "запусти сборку", "проверь логи", "сделай пулл", "закоммить изменения",
    "создай ветку", "смержи ветки", "откати коммит", "добавь зависимость",
    "обнови пакеты", "почисти кэш", "перезапусти сервер", "проверь статус",
    "открой консоль", "посмотри ошибки", "исправь баг", "добавь тест",
    "напиши документацию", "обнови версию", "задеплой на прод", "откати релиз",
    "настрой окружение", "создай контейнер", "запусти миграции", "сделай бэкап",
    "восстанови базу", "проверь подключение", "обнови сертификат", "настрой прокси",
]

# ============================================================================
# GENERATOR FUNCTIONS
# ============================================================================

def generate_company_tests(existing_ids: Set[str]) -> List[TestCase]:
    """Generate tests for company/service names (should NOT convert)."""
    tests = []
    counter = 1

    all_companies = (
        TECH_GIANTS + CLOUD_PROVIDERS + DEV_TOOLS + AI_SERVICES +
        DATABASES + FRAMEWORKS + RUSSIAN_SERVICES + CRYPTO_SERVICES +
        SOCIAL_MEDIA + GAMING
    )

    for company in all_companies:
        test_id = f"mega_company_{counter:04d}"
        if test_id not in existing_ids:
            tests.append(TestCase(
                id=test_id,
                category="companies_services",
                input=company,
                expected=company,
                should_convert=False,
                notes="Valid company/service name"
            ))
            counter += 1

    return tests

def generate_cli_tests(existing_ids: Set[str]) -> List[TestCase]:
    """Generate tests for CLI commands (should NOT convert)."""
    tests = []
    counter = 1

    all_commands = (
        GIT_COMMANDS + NPM_COMMANDS + YARN_COMMANDS + PNPM_COMMANDS +
        DOCKER_COMMANDS + KUBECTL_COMMANDS + SYSTEM_COMMANDS +
        PYTHON_COMMANDS + RUST_COMMANDS + GO_COMMANDS
    )

    for cmd in all_commands:
        test_id = f"mega_cli_{counter:04d}"
        if test_id not in existing_ids:
            tests.append(TestCase(
                id=test_id,
                category="cli_commands",
                input=cmd,
                expected=cmd,
                should_convert=False,
                notes="Valid CLI command"
            ))
            counter += 1

    return tests

def generate_identifier_tests(existing_ids: Set[str]) -> List[TestCase]:
    """Generate tests for programming identifiers (should NOT convert)."""
    tests = []
    counter = 1

    for ident in COMMON_IDENTIFIERS + FILE_NAMES:
        test_id = f"mega_ident_{counter:04d}"
        if test_id not in existing_ids:
            tests.append(TestCase(
                id=test_id,
                category="identifiers",
                input=ident,
                expected=ident,
                should_convert=False,
                notes="Valid identifier/filename"
            ))
            counter += 1

    return tests

def generate_english_stress_tests(existing_ids: Set[str]) -> List[TestCase]:
    """Generate valid English sentences that should NOT convert."""
    tests = []
    counter = 1

    for sentence in VALID_ENGLISH_SENTENCES:
        test_id = f"mega_en_stress_{counter:04d}"
        if test_id not in existing_ids:
            tests.append(TestCase(
                id=test_id,
                category="stress_tests_en",
                input=sentence,
                expected=sentence,
                should_convert=False,
                notes="Valid English sentence"
            ))
            counter += 1

    return tests

def generate_russian_word_tests(existing_ids: Set[str]) -> List[TestCase]:
    """Generate corrupted Russian words (should convert)."""
    tests = []
    counter = 1

    for word in RUSSIAN_COMMON_WORDS:
        corrupted = convert_ru_to_en(word)
        test_id = f"mega_ru_word_{counter:04d}"
        if test_id not in existing_ids:
            tests.append(TestCase(
                id=test_id,
                category="ru_common_words",
                input=corrupted,
                expected=word,
                should_convert=True,
                notes="Corrupted Russian word"
            ))
            counter += 1

    return tests

def generate_russian_phrase_tests(existing_ids: Set[str]) -> List[TestCase]:
    """Generate corrupted Russian IT phrases (should convert)."""
    tests = []
    counter = 1

    for phrase in RUSSIAN_IT_PHRASES:
        corrupted = convert_ru_to_en(phrase)
        test_id = f"mega_ru_phrase_{counter:04d}"
        if test_id not in existing_ids:
            tests.append(TestCase(
                id=test_id,
                category="ru_phrases",
                input=corrupted,
                expected=phrase,
                should_convert=True,
                notes="Corrupted Russian IT phrase"
            ))
            counter += 1

    return tests

def generate_uppercase_tests(existing_ids: Set[str]) -> List[TestCase]:
    """Generate uppercase variants."""
    tests = []
    counter = 1

    # Corrupted Russian uppercase (should convert)
    ru_upper_words = ["ПРИВЕТ", "СРОЧНО", "ВАЖНО", "ВНИМАНИЕ", "ОШИБКА", "ГОТОВО"]
    for word in ru_upper_words:
        corrupted = convert_ru_to_en(word)
        test_id = f"mega_upper_{counter:04d}"
        if test_id not in existing_ids:
            tests.append(TestCase(
                id=test_id,
                category="uppercase",
                input=corrupted,
                expected=word,
                should_convert=True,
                notes="Corrupted Russian uppercase"
            ))
            counter += 1

    # Valid English uppercase (should NOT convert)
    en_upper_words = ["API", "URL", "HTTP", "JSON", "HTML", "CSS", "SQL", "XML",
                      "README", "TODO", "FIXME", "NOTE", "WARNING", "ERROR"]
    for word in en_upper_words:
        test_id = f"mega_upper_{counter:04d}"
        if test_id not in existing_ids:
            tests.append(TestCase(
                id=test_id,
                category="uppercase",
                input=word,
                expected=word,
                should_convert=False,
                notes="Valid English uppercase"
            ))
            counter += 1

    return tests

def generate_mixed_tests(existing_ids: Set[str]) -> List[TestCase]:
    """Generate mixed language tests."""
    tests = []
    counter = 1

    # Code-switching examples (Russian + English terms)
    code_switch = [
        ("pfgecnb build", "запусти build"),
        ("cltkfq commit", "сделай commit"),
        ("ghj,ktv c deploy", "проблем с deploy"),
        ("j,yjdb API", "обнови API"),
        ("gjxtve crash", "почему crash"),
        ("cltkfq merge", "сделай merge"),
        ("pfgecnb test", "запусти test"),
        ("j,yjdb config", "обнови config"),
    ]

    for corrupted, expected in code_switch:
        test_id = f"mega_mixed_{counter:04d}"
        if test_id not in existing_ids:
            tests.append(TestCase(
                id=test_id,
                category="code_switching",
                input=corrupted,
                expected=expected,
                should_convert=True,
                notes="Code-switching RU+EN"
            ))
            counter += 1

    return tests

def generate_short_word_tests(existing_ids: Set[str]) -> List[TestCase]:
    """Generate short word tests (1-3 chars)."""
    tests = []
    counter = 1

    # Russian prepositions/particles corrupted
    ru_short = ["в", "на", "из", "за", "по", "к", "у", "о", "и", "а", "но", "да",
                "не", "ни", "бы", "ли", "же", "вот", "вон", "тут", "там", "где"]

    for word in ru_short:
        corrupted = convert_ru_to_en(word)
        if len(corrupted) <= 3 and corrupted != word:
            test_id = f"mega_short_{counter:04d}"
            if test_id not in existing_ids:
                tests.append(TestCase(
                    id=test_id,
                    category="short_words",
                    input=corrupted,
                    expected=word,
                    should_convert=True,
                    notes="Short Russian word corrupted"
                ))
                counter += 1

    # Valid English short words (should NOT convert)
    en_short = ["a", "I", "on", "in", "at", "to", "of", "by", "is", "it",
                "be", "do", "go", "no", "ok", "up", "us", "we", "if", "or"]

    for word in en_short:
        test_id = f"mega_short_{counter:04d}"
        if test_id not in existing_ids:
            tests.append(TestCase(
                id=test_id,
                category="short_words",
                input=word,
                expected=word,
                should_convert=False,
                notes="Valid English short word"
            ))
            counter += 1

    return tests

def generate_sensitive_tests(existing_ids: Set[str]) -> List[TestCase]:
    """Generate sensitive data tests (should NEVER convert)."""
    tests = []
    counter = 1

    sensitive_patterns = [
        # URLs
        "https://api.github.com/v1/users",
        "https://example.com/path?query=value",
        "http://localhost:3000/api/auth",
        "ftp://files.server.com/download",
        # Emails
        "user@example.com",
        "admin@company.org",
        "support@service.io",
        # IPs
        "192.168.1.1",
        "10.0.0.1",
        "127.0.0.1:8080",
        # Paths
        "/usr/local/bin/python",
        "/home/user/.config",
        "C:\\Users\\Admin\\Documents",
        "./src/components/App.tsx",
        # UUIDs
        "550e8400-e29b-41d4-a716-446655440000",
        "123e4567-e89b-12d3-a456-426614174000",
        # API keys (fake patterns)
        "sk_live_abc123xyz789",
        "pk_test_1234567890",
        "api_key_abcdefghij",
        # Hashes
        "a1b2c3d4e5f6g7h8i9j0",
        "sha256:abc123def456",
        # Tokens
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0",
        "Bearer token_abc123",
    ]

    for pattern in sensitive_patterns:
        test_id = f"mega_sensitive_{counter:04d}"
        if test_id not in existing_ids:
            tests.append(TestCase(
                id=test_id,
                category="sensitive_data",
                input=pattern,
                expected=pattern,
                should_convert=False,
                notes="Sensitive data - never convert"
            ))
            counter += 1

    return tests

def main():
    """Main function to generate and merge tests."""
    corpus_path = "../test_corpus_v2.json"

    # Load existing tests
    if os.path.exists(corpus_path):
        with open(corpus_path, 'r', encoding='utf-8') as f:
            existing_tests = json.load(f)
        print(f"Existing tests: {len(existing_tests)}")
    else:
        existing_tests = []
        print("No existing corpus found, starting fresh")

    # Track existing IDs and (input, expected) pairs for deduplication
    existing_ids = {t['id'] for t in existing_tests}
    existing_pairs = {(t['input'], t['expected']) for t in existing_tests}

    # Generate new tests
    all_new_tests = []

    generators = [
        ("Companies/Services", generate_company_tests),
        ("CLI Commands", generate_cli_tests),
        ("Identifiers", generate_identifier_tests),
        ("English Stress", generate_english_stress_tests),
        ("Russian Words", generate_russian_word_tests),
        ("Russian Phrases", generate_russian_phrase_tests),
        ("Uppercase", generate_uppercase_tests),
        ("Mixed/Code-switching", generate_mixed_tests),
        ("Short Words", generate_short_word_tests),
        ("Sensitive Data", generate_sensitive_tests),
    ]

    for name, generator in generators:
        tests = generator(existing_ids)
        unique_tests = []
        for t in tests:
            pair = (t.input, t.expected)
            if pair not in existing_pairs:
                existing_pairs.add(pair)
                existing_ids.add(t.id)
                unique_tests.append(t)
        print(f"  {name}: {len(unique_tests)} unique tests")
        all_new_tests.extend(unique_tests)

    print(f"\nTotal new tests: {len(all_new_tests)}")

    # Merge with existing
    merged = existing_tests + [asdict(t) for t in all_new_tests]

    # Save
    with open(corpus_path, 'w', encoding='utf-8') as f:
        json.dump(merged, f, ensure_ascii=False, indent=2)

    print(f"\nTotal tests: {len(merged)}")
    print(f"Saved to: {os.path.abspath(corpus_path)}")

    # Statistics
    should_convert = sum(1 for t in merged if t['should_convert'])
    should_not = len(merged) - should_convert
    print(f"\nStatistics:")
    print(f"  Should convert: {should_convert} ({100*should_convert/len(merged):.1f}%)")
    print(f"  Should NOT convert: {should_not} ({100*should_not/len(merged):.1f}%)")

if __name__ == "__main__":
    main()
