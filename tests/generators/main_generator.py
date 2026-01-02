#!/usr/bin/env python3
"""
Main Test Generator for TextSwitcher
Generates comprehensive test dataset (~15,000 tests) for QWERTY ↔ ЙЦУКЕН validation.

Usage:
    python main_generator.py

Output:
    ../test_corpus_v2.json
"""

import json
import os
import re
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass, asdict
from pathlib import Path

# MARK: - QWERTY ↔ ЙЦУКЕН Mapping

# English QWERTY -> Russian ЙЦУКЕН (when typing Russian with EN layout)
EN_TO_RU = {
    'q': 'й', 'w': 'ц', 'e': 'у', 'r': 'к', 't': 'е', 'y': 'н', 'u': 'г', 'i': 'ш', 'o': 'щ', 'p': 'з',
    '[': 'х', ']': 'ъ', 'a': 'ф', 's': 'ы', 'd': 'в', 'f': 'а', 'g': 'п', 'h': 'р', 'j': 'о', 'k': 'л',
    'l': 'д', ';': 'ж', "'": 'э', 'z': 'я', 'x': 'ч', 'c': 'с', 'v': 'м', 'b': 'и', 'n': 'т', 'm': 'ь',
    ',': 'б', '.': 'ю', '/': '.', '`': 'ё',
    # Uppercase
    'Q': 'Й', 'W': 'Ц', 'E': 'У', 'R': 'К', 'T': 'Е', 'Y': 'Н', 'U': 'Г', 'I': 'Ш', 'O': 'Щ', 'P': 'З',
    '{': 'Х', '}': 'Ъ', 'A': 'Ф', 'S': 'Ы', 'D': 'В', 'F': 'А', 'G': 'П', 'H': 'Р', 'J': 'О', 'K': 'Л',
    'L': 'Д', ':': 'Ж', '"': 'Э', 'Z': 'Я', 'X': 'Ч', 'C': 'С', 'V': 'М', 'B': 'И', 'N': 'Т', 'M': 'Ь',
    '<': 'Б', '>': 'Ю', '?': ',', '~': 'Ё',
}

# Russian ЙЦУКЕН -> English QWERTY (when typing English with RU layout)
RU_TO_EN = {
    'й': 'q', 'ц': 'w', 'у': 'e', 'к': 'r', 'е': 't', 'н': 'y', 'г': 'u', 'ш': 'i', 'щ': 'o', 'з': 'p',
    'х': '[', 'ъ': ']', 'ф': 'a', 'ы': 's', 'в': 'd', 'а': 'f', 'п': 'g', 'р': 'h', 'о': 'j', 'л': 'k',
    'д': 'l', 'ж': ';', 'э': "'", 'я': 'z', 'ч': 'x', 'с': 'c', 'м': 'v', 'и': 'b', 'т': 'n', 'ь': 'm',
    'б': ',', 'ю': '.', 'ё': '`',
    # Uppercase
    'Й': 'Q', 'Ц': 'W', 'У': 'E', 'К': 'R', 'Е': 'T', 'Н': 'Y', 'Г': 'U', 'Ш': 'I', 'Щ': 'O', 'З': 'P',
    'Х': '{', 'Ъ': '}', 'Ф': 'A', 'Ы': 'S', 'В': 'D', 'А': 'F', 'П': 'G', 'Р': 'H', 'О': 'J', 'Л': 'K',
    'Д': 'L', 'Ж': ':', 'Э': '"', 'Я': 'Z', 'Ч': 'X', 'С': 'C', 'М': 'V', 'И': 'B', 'Т': 'N', 'Ь': 'M',
    'Б': '<', 'Ю': '>', 'Ё': '~',
}

def convert_en_to_ru(text: str) -> str:
    """Convert text typed in EN layout to RU characters."""
    return ''.join(EN_TO_RU.get(c, c) for c in text)

def convert_ru_to_en(text: str) -> str:
    """Convert text typed in RU layout to EN characters."""
    return ''.join(RU_TO_EN.get(c, c) for c in text)

def corrupt_ru_word(word: str) -> str:
    """Corrupt Russian word as if typed with EN layout (ghbdtn -> привет)."""
    return convert_ru_to_en(word)

def corrupt_en_word(word: str) -> str:
    """Corrupt English word as if typed with RU layout (руддщ -> hello)."""
    return convert_en_to_ru(word)


# MARK: - Test Case Model

@dataclass
class TestCase:
    id: str
    category: str
    input: str
    expected: str
    should_convert: bool
    notes: str = ""

    def to_dict(self) -> dict:
        d = asdict(self)
        if not d['notes']:
            del d['notes']
        return d


# MARK: - Wordlist Loaders

def load_wordlist(filename: str) -> List[str]:
    """Load wordlist from file, one word per line."""
    filepath = Path(__file__).parent.parent / "data" / "wordlists" / filename
    if not filepath.exists():
        print(f"Warning: {filepath} not found")
        return []
    with open(filepath, 'r', encoding='utf-8') as f:
        return [line.strip() for line in f if line.strip()]

def load_json(filename: str):
    """Load JSON file."""
    filepath = Path(__file__).parent.parent.parent / "Dictum" / "Resources" / filename
    if not filepath.exists():
        print(f"Warning: {filepath} not found")
        return {}
    with open(filepath, 'r', encoding='utf-8') as f:
        return json.load(f)

def load_tech_buzzwords() -> List[str]:
    """Load all tech buzzwords from categorized JSON."""
    data = load_json("tech_buzzwords_2025.json")
    if not data:
        return []

    all_words = []
    for category, words in data.items():
        if isinstance(words, list):
            all_words.extend(words)

    return list(set(all_words))  # Remove duplicates


# MARK: - Category Generators

def generate_ru_common_words(limit: int = 2000) -> List[TestCase]:
    """Generate tests for common Russian words (typed with EN layout)."""
    tests = []
    words = load_wordlist("ru_top_2000.txt")[:limit]

    for i, word in enumerate(words):
        if len(word) < 2:
            continue
        corrupted = corrupt_ru_word(word)
        # Skip if corruption produces same text (numbers, punctuation)
        if corrupted == word:
            continue
        tests.append(TestCase(
            id=f"ru_common_{i:04d}",
            category="ru_common_words",
            input=corrupted,
            expected=word,
            should_convert=True
        ))

    return tests

def generate_en_common_words(limit: int = 2000) -> List[TestCase]:
    """Generate tests for common English words (typed with RU layout)."""
    tests = []
    words = load_wordlist("en_top_2000.txt")[:limit]

    for i, word in enumerate(words):
        if len(word) < 2:
            continue
        corrupted = corrupt_en_word(word)
        # Skip if corruption produces same text
        if corrupted == word:
            continue
        tests.append(TestCase(
            id=f"en_common_{i:04d}",
            category="en_common_words",
            input=corrupted,
            expected=word,
            should_convert=True
        ))

    return tests

def generate_tech_buzzwords() -> List[TestCase]:
    """Generate tests for tech buzzwords (should NOT convert)."""
    tests = []
    buzzwords = load_tech_buzzwords()

    for i, word in enumerate(buzzwords):
        if len(word) < 2:
            continue

        # Tech buzzwords should NOT be converted
        tests.append(TestCase(
            id=f"buzz_{i:04d}",
            category="tech_buzzwords",
            input=word,
            expected=word,
            should_convert=False,
            notes="tech_term"
        ))

        # Also test corrupted version (typed with wrong layout)
        corrupted = corrupt_en_word(word)
        if corrupted != word and len(corrupted) > 1:
            tests.append(TestCase(
                id=f"buzz_corrupt_{i:04d}",
                category="tech_buzzwords_corrupted",
                input=corrupted,
                expected=word,
                should_convert=True,
                notes="tech_term_restore"
            ))

    return tests

def generate_companies_services() -> List[TestCase]:
    """Generate tests for company/service names (should NOT convert when typed correctly)."""
    tests = []

    # Comprehensive list of companies and services
    companies = [
        # Tech Giants
        "Google", "Apple", "Microsoft", "Amazon", "Meta", "Netflix", "Tesla", "Nvidia",
        "Intel", "AMD", "IBM", "Oracle", "Salesforce", "Adobe", "Cisco", "Dell", "HP",
        "Lenovo", "Samsung", "Sony", "Huawei", "Xiaomi", "ASUS", "Acer", "LG",

        # Cloud Providers
        "AWS", "Azure", "GCP", "DigitalOcean", "Linode", "Vultr", "Hetzner", "OVH",
        "Cloudflare", "Vercel", "Netlify", "Heroku", "Railway", "Render", "Supabase",

        # Dev Tools & Platforms
        "GitHub", "GitLab", "Bitbucket", "Jira", "Confluence", "Notion", "Figma",
        "Sketch", "Miro", "Trello", "Asana", "Linear", "Slack", "Discord", "Zoom",
        "Teams", "Webex", "Postman", "Insomnia", "Bruno",

        # Databases
        "MongoDB", "PostgreSQL", "MySQL", "Redis", "Elasticsearch", "Cassandra",
        "DynamoDB", "PlanetScale", "Neon", "Turso", "CockroachDB", "ClickHouse",
        "TimescaleDB", "InfluxDB", "Neo4j", "ArangoDB",

        # AI/ML Services
        "OpenAI", "Anthropic", "Midjourney", "ElevenLabs", "Replicate", "RunwayML",
        "ChatGPT", "Claude", "Gemini", "Copilot", "Perplexity", "Cursor",

        # Payment & Fintech
        "Stripe", "PayPal", "Square", "Klarna", "Affirm", "Plaid", "Wise", "Revolut",
        "Brex", "Mercury", "Venmo", "CashApp",

        # Social Media
        "Twitter", "Instagram", "TikTok", "YouTube", "LinkedIn", "Pinterest",
        "Reddit", "Snapchat", "Telegram", "WhatsApp", "Signal", "Mastodon",

        # E-commerce
        "Shopify", "WooCommerce", "Magento", "BigCommerce", "Etsy", "eBay",
        "AliExpress", "Alibaba",

        # Russian Services
        "Yandex", "VKontakte", "Ozon", "Wildberries", "Avito", "HeadHunter",
        "Tinkoff", "Sberbank", "Alfabank", "Lamoda", "Delivery", "Samokat",

        # Gaming & Entertainment
        "Steam", "Unity", "Unreal", "Roblox", "Twitch", "PlayStation", "Xbox",
        "Nintendo", "Spotify", "SoundCloud", "Deezer",

        # Productivity
        "Dropbox", "OneDrive", "iCloud", "Evernote", "Obsidian", "Roam",
        "Logseq", "Todoist", "TickTick", "Fantastical",

        # Development
        "Docker", "Kubernetes", "Terraform", "Ansible", "Jenkins", "CircleCI",
        "TravisCI", "Datadog", "Grafana", "Prometheus", "Sentry", "LogRocket",

        # Frameworks & Libraries (short names)
        "React", "Vue", "Angular", "Svelte", "Next", "Nuxt", "Remix", "Astro",
        "Django", "Flask", "FastAPI", "Rails", "Laravel", "Spring", "Express",
        "Nest", "Deno", "Bun", "Vite", "Webpack", "Rollup", "ESBuild",
    ]

    for i, company in enumerate(companies):
        # Company name typed correctly - should NOT convert
        tests.append(TestCase(
            id=f"company_{i:04d}",
            category="companies_services",
            input=company,
            expected=company,
            should_convert=False,
            notes="brand_name"
        ))

        # Company name typed with RU layout - should convert back
        corrupted = corrupt_en_word(company)
        if corrupted != company:
            tests.append(TestCase(
                id=f"company_corrupt_{i:04d}",
                category="companies_services_corrupted",
                input=corrupted,
                expected=company,
                should_convert=True,
                notes="brand_restore"
            ))

    return tests

def generate_short_words() -> List[TestCase]:
    """Generate tests for short words (1-3 chars) - prepositions, conjunctions, particles."""
    tests = []

    # Russian short words
    ru_short = [
        # Prepositions
        "в", "на", "из", "за", "по", "до", "от", "с", "к", "у", "о", "об",
        "при", "для", "без", "под", "над", "про",
        # Conjunctions
        "и", "а", "но", "да", "или", "что", "как", "так", "то",
        # Particles
        "не", "ни", "бы", "ли", "же", "ведь", "вот", "вон", "даже", "уже", "еще",
        # Pronouns
        "я", "ты", "он", "она", "оно", "мы", "вы", "они", "кто", "что", "это", "то",
        # Common short
        "да", "нет", "все", "вся", "сам", "там", "тут", "где", "как", "так",
    ]

    # English short words
    en_short = [
        # Articles
        "a", "an", "the",
        # Pronouns
        "I", "me", "my", "we", "us", "he", "she", "it", "they", "who", "what",
        # Prepositions
        "in", "on", "at", "to", "of", "by", "for", "with", "from", "up", "out",
        # Conjunctions
        "and", "or", "but", "if", "so", "as", "than", "nor",
        # Common
        "is", "be", "do", "go", "no", "ok", "hi", "oh", "yes", "yet", "not",
        "can", "may", "get", "let", "put", "set", "run", "see", "new", "old",
    ]

    # Generate RU short word tests
    for i, word in enumerate(ru_short):
        corrupted = corrupt_ru_word(word)
        if corrupted != word:
            tests.append(TestCase(
                id=f"short_ru_{i:04d}",
                category="short_words_ru",
                input=corrupted,
                expected=word,
                should_convert=True,
                notes="short_ru"
            ))

    # Generate EN short word tests
    for i, word in enumerate(en_short):
        corrupted = corrupt_en_word(word)
        if corrupted != word:
            tests.append(TestCase(
                id=f"short_en_{i:04d}",
                category="short_words_en",
                input=corrupted,
                expected=word,
                should_convert=True,
                notes="short_en"
            ))

    return tests

def generate_shifted_symbols() -> List[TestCase]:
    """Generate tests for shifted symbol combinations."""
    tests = []

    # Words with shifted symbols that map to Russian letters
    shifted_tests = [
        # { -> Х
        ("{jhjij", "Хорошо"),
        ("{jnm", "Хоть"),
        ("{elj;ybr", "Художник"),

        # } -> Ъ (rare)
        ("}tcnm", "Ъесть"),  # hypothetical

        # < -> Б
        ("<jkm", "Боль"),
        ("<eltn", "Будет"),
        ("<scnhj", "Быстро"),

        # > -> Ю
        (">kz", "Юля"),
        (">ujckfdbz", "Югославия"),

        # : -> Ж
        (":bnm", "Жить"),
        (":tkfybt", "Желание"),
        (":ehyfk", "Журнал"),

        # " -> Э
        ("\"nj", "Это"),
        ("\"vjwbz", "Эмоция"),
        ("\"ythubz", "Энергия"),

        # ~ -> Ё
        ("~k", "Ёл"),
        ("~;br", "Ёжик"),

        # ? -> ,
        ("ghbdtn?", "привет,"),
    ]

    for i, (inp, exp) in enumerate(shifted_tests):
        tests.append(TestCase(
            id=f"shifted_{i:04d}",
            category="shifted_symbols",
            input=inp,
            expected=exp,
            should_convert=True,
            notes="shifted_key"
        ))

    return tests

def generate_code_switching() -> List[TestCase]:
    """Generate tests for code-switching (RU text with EN terms)."""
    tests = []

    code_switch_examples = [
        # Format: (corrupted_input, expected_output)
        ("Запусти ,bkl", "Запусти build"),
        ("Сделай gekk", "Сделай pull"),
        ("Проверь kju", "Проверь log"),
        ("Открой ащдвук", "Открой folder"),
        ("Закрой ,hfecth", "Закрой browser"),
        ("Запушь rjvvbn", "Запушь commit"),
        ("Мёржни ,hfyxb", "Мёржни branch"),
        ("Сделай htdm.", "Сделай review"),
        ("Открой ntcns", "Открой tests"),
        ("Запусти cthdth", "Запусти server"),
        ("Проверь kjub", "Проверь logs"),
        ("Включи lt,fu", "Включи debug"),
        ("Выключи rtibyju", "Выключи caching"),
        ("Обнови gfrfutc", "Обнови packages"),
        ("Удали rfi", "Удали cache"),
        # Mixed RU + EN in IT communication
        ("ghbdtn мир", "привет мир"),  # "привет" corrupted, "мир" already RU
        ("hello vbh", "hello мир"),  # "hello" EN, "мир" corrupted
    ]

    for i, (inp, exp) in enumerate(code_switch_examples):
        tests.append(TestCase(
            id=f"codeswitch_{i:04d}",
            category="code_switching",
            input=inp,
            expected=exp,
            should_convert=True,
            notes="mixed_lang"
        ))

    return tests

def generate_sensitive_data() -> List[TestCase]:
    """Generate tests for sensitive data that should NOT be converted."""
    tests = []

    sensitive_patterns = [
        # Emails
        ("user@example.com", "email"),
        ("test.user@gmail.com", "email"),
        ("admin@company.ru", "email"),

        # URLs
        ("https://github.com", "url"),
        ("http://localhost:3000", "url"),
        ("https://api.example.com/v1", "url"),
        ("www.google.com", "url"),

        # Paths
        ("/usr/local/bin", "path"),
        ("/home/user/.config", "path"),
        ("~/Documents/file.txt", "path"),
        ("./src/index.ts", "path"),
        ("../parent/file.js", "path"),

        # UUIDs
        ("550e8400-e29b-41d4-a716-446655440000", "uuid"),
        ("a1b2c3d4-e5f6-7890-abcd-ef1234567890", "uuid"),

        # API Keys (patterns)
        ("sk_live_abc123xyz789", "api_key"),
        ("pk_test_1234567890", "api_key"),
        ("AKIAIOSFODNN7EXAMPLE", "api_key"),

        # IP addresses
        ("192.168.1.1", "ip"),
        ("10.0.0.1", "ip"),
        ("127.0.0.1", "ip"),
        ("::1", "ipv6"),

        # Phone numbers
        ("+7-999-123-45-67", "phone"),
        ("+1-555-123-4567", "phone"),
        ("8-800-555-35-35", "phone"),

        # Dates
        ("2024-12-31", "date"),
        ("31.12.2024", "date"),
        ("12/31/2024", "date"),

        # Times
        ("14:30:00", "time"),
        ("23:59:59", "time"),

        # Hashes
        ("a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4", "hash"),
        ("sha256:abc123def456", "hash"),

        # Tokens (JWT-like)
        ("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIx", "token"),

        # Version numbers
        ("v1.2.3", "version"),
        ("2.0.0-beta.1", "version"),

        # File extensions should be preserved
        ("file.json", "filename"),
        ("script.py", "filename"),
        ("index.html", "filename"),
        ("style.css", "filename"),
    ]

    for i, (data, data_type) in enumerate(sensitive_patterns):
        tests.append(TestCase(
            id=f"sensitive_{i:04d}",
            category="sensitive_data",
            input=data,
            expected=data,
            should_convert=False,
            notes=data_type
        ))

    return tests

def generate_cli_commands() -> List[TestCase]:
    """Generate tests for CLI commands (should NOT convert)."""
    tests = []

    cli_commands = [
        # Git
        "git push", "git pull", "git commit", "git merge", "git rebase",
        "git checkout", "git branch", "git log", "git status", "git diff",
        "git add", "git reset", "git stash", "git fetch", "git clone",

        # NPM/Yarn/PNPM
        "npm install", "npm run build", "npm run test", "npm run dev",
        "yarn add", "yarn install", "pnpm install", "pnpm build",

        # Docker
        "docker build", "docker run", "docker compose up", "docker ps",
        "docker stop", "docker rm", "docker images", "docker pull",

        # Python
        "pip install", "python main.py", "pytest", "python -m venv",

        # System
        "ls -la", "cd src", "mkdir test", "rm -rf", "chmod +x",
        "cat file.txt", "grep pattern", "curl localhost",

        # macOS
        "brew install", "brew update", "open .", "pbcopy", "pbpaste",

        # Kubernetes
        "kubectl get pods", "kubectl apply", "kubectl logs", "kubectl exec",
    ]

    for i, cmd in enumerate(cli_commands):
        tests.append(TestCase(
            id=f"cli_{i:04d}",
            category="cli_commands",
            input=cmd,
            expected=cmd,
            should_convert=False,
            notes="cli"
        ))

    # Also test corrupted CLI commands (typed with RU layout)
    cli_single_words = ["git", "npm", "docker", "pip", "brew", "kubectl", "curl", "wget"]
    for i, cmd in enumerate(cli_single_words):
        corrupted = corrupt_en_word(cmd)
        if corrupted != cmd:
            tests.append(TestCase(
                id=f"cli_corrupt_{i:04d}",
                category="cli_commands_corrupted",
                input=corrupted,
                expected=cmd,
                should_convert=True,
                notes="cli_restore"
            ))

    return tests

def generate_file_paths() -> List[TestCase]:
    """Generate tests for file paths and config files."""
    tests = []

    config_files = [
        ".gitignore", ".env", ".dockerignore", ".eslintrc", ".prettierrc",
        "package.json", "tsconfig.json", "webpack.config.js", "vite.config.ts",
        "Dockerfile", "docker-compose.yml", "Makefile", "CMakeLists.txt",
        "requirements.txt", "setup.py", "pyproject.toml", "Cargo.toml",
        "README.md", "CHANGELOG.md", "LICENSE", "CONTRIBUTING.md",
    ]

    for i, filename in enumerate(config_files):
        # Config file typed correctly - should NOT convert
        tests.append(TestCase(
            id=f"file_{i:04d}",
            category="file_paths",
            input=filename,
            expected=filename,
            should_convert=False,
            notes="config_file"
        ))

    # Test corrupted versions
    file_names_to_corrupt = ["package", "config", "index", "main", "server", "client"]
    for i, name in enumerate(file_names_to_corrupt):
        corrupted = corrupt_en_word(name)
        if corrupted != name:
            tests.append(TestCase(
                id=f"file_corrupt_{i:04d}",
                category="file_paths_corrupted",
                input=f"{corrupted}.json",
                expected=f"{name}.json",
                should_convert=True,
                notes="filename_restore"
            ))

    return tests

def generate_camelcase_snake() -> List[TestCase]:
    """Generate tests for CamelCase and snake_case identifiers."""
    tests = []

    identifiers = [
        # CamelCase
        "getUserById", "setUserName", "handleClick", "onSubmit", "fetchData",
        "createNewUser", "deleteItem", "updateRecord", "validateForm",
        "processPayment", "sendNotification", "loadMoreItems",

        # snake_case
        "get_user_by_id", "set_user_name", "handle_click", "on_submit",
        "fetch_data", "create_new_user", "delete_item", "update_record",
        "validate_form", "process_payment", "send_notification",

        # SCREAMING_SNAKE_CASE
        "MAX_VALUE", "MIN_SIZE", "DEFAULT_TIMEOUT", "API_BASE_URL",
        "DATABASE_URL", "SECRET_KEY", "DEBUG_MODE",
    ]

    for i, ident in enumerate(identifiers):
        # Identifiers typed correctly - should NOT convert (they're code)
        tests.append(TestCase(
            id=f"ident_{i:04d}",
            category="identifiers",
            input=ident,
            expected=ident,
            should_convert=False,
            notes="code_identifier"
        ))

    return tests

def generate_uppercase() -> List[TestCase]:
    """Generate tests for UPPERCASE words."""
    tests = []

    # Russian uppercase (corrupted from EN layout)
    ru_upper = ["ПРИВЕТ", "ВНИМАНИЕ", "ВАЖНО", "СРОЧНО", "ОШИБКА", "ТЕСТ"]
    for i, word in enumerate(ru_upper):
        corrupted = corrupt_ru_word(word)
        if corrupted != word:
            tests.append(TestCase(
                id=f"upper_ru_{i:04d}",
                category="uppercase_ru",
                input=corrupted,
                expected=word,
                should_convert=True
            ))

    # English uppercase abbreviations - should NOT convert
    en_upper = [
        "API", "URL", "HTTP", "HTTPS", "JSON", "XML", "HTML", "CSS", "SQL",
        "REST", "CRUD", "JWT", "OAuth", "SSL", "TLS", "DNS", "CDN",
        "AWS", "GCP", "SaaS", "PaaS", "IaaS", "SDK", "CLI", "GUI",
        "README", "TODO", "FIXME", "NOTE", "WARN", "DEBUG", "INFO",
    ]
    for i, abbr in enumerate(en_upper):
        tests.append(TestCase(
            id=f"upper_en_{i:04d}",
            category="uppercase_en",
            input=abbr,
            expected=abbr,
            should_convert=False,
            notes="abbreviation"
        ))

    return tests

def generate_punctuation() -> List[TestCase]:
    """Generate tests for words with punctuation."""
    tests = []

    # Russian words with punctuation (corrupted)
    punct_tests = [
        ("ghbdtn!", "привет!"),
        ("ghbdtn,", "привет,"),
        ("ghbdtn.", "привет."),
        ("ghbdtn?", "привет,"),  # ? -> , on RU layout
        ("ghbdtn...", "привет..."),
        ("(ghbdtn)", "(привет)"),
        ("[ghbdtn]", "[привет]"),
        ("\"ghbdtn\"", "\"привет\""),
        ("'ghbdtn'", "'привет'"),
        ("ghbdtn:", "привет:"),
        ("ghbdtn;", "привет;"),
        ("-ghbdtn-", "-привет-"),
    ]

    for i, (inp, exp) in enumerate(punct_tests):
        tests.append(TestCase(
            id=f"punct_{i:04d}",
            category="punctuation",
            input=inp,
            expected=exp,
            should_convert=True
        ))

    return tests

def generate_numbers_mixed() -> List[TestCase]:
    """Generate tests for mixed text with numbers."""
    tests = []

    mixed_tests = [
        # Numbers should be preserved
        ("ntcn123", "тест123"),
        ("ghbdtn2024", "привет2024"),
        ("2024ujl", "2024год"),
        ("d3", "в3"),

        # English with numbers - should NOT convert
        ("test123", "test123", False),
        ("user42", "user42", False),
        ("v2", "v2", False),
        ("config2", "config2", False),
        ("stage3", "stage3", False),

        # Mixed language with numbers
        ("File1", "File1", False),
        ("День1", "День1", False),
    ]

    for i, item in enumerate(mixed_tests):
        if len(item) == 2:
            inp, exp = item
            should_conv = True
        else:
            inp, exp, should_conv = item

        tests.append(TestCase(
            id=f"mixed_{i:04d}",
            category="numbers_mixed",
            input=inp,
            expected=exp,
            should_convert=should_conv
        ))

    return tests

def generate_stress_tests() -> List[TestCase]:
    """Generate stress tests - valid text that should NOT be converted."""
    tests = []

    # Valid English sentences
    en_sentences = [
        "The quick brown fox jumps over the lazy dog",
        "Hello world",
        "This is a test",
        "Good morning",
        "Thank you very much",
        "Please wait a moment",
        "I need help with this",
        "Can you help me",
        "What time is it",
        "Where are you from",
        "How are you doing today",
        "Nice to meet you",
        "See you later",
        "Have a nice day",
        "Welcome to the team",
    ]

    for i, sentence in enumerate(en_sentences):
        tests.append(TestCase(
            id=f"stress_en_{i:04d}",
            category="stress_test_en",
            input=sentence,
            expected=sentence,
            should_convert=False,
            notes="valid_en"
        ))

    # Valid Russian sentences
    ru_sentences = [
        "Привет мир",
        "Как дела",
        "Спасибо большое",
        "До свидания",
        "Доброе утро",
        "Добрый день",
        "Добрый вечер",
        "Хорошего дня",
        "Удачи тебе",
        "Пока пока",
        "Рад познакомиться",
        "Очень приятно",
        "Давай созвонимся",
        "Перезвони пожалуйста",
        "Жду ответа",
    ]

    for i, sentence in enumerate(ru_sentences):
        tests.append(TestCase(
            id=f"stress_ru_{i:04d}",
            category="stress_test_ru",
            input=sentence,
            expected=sentence,
            should_convert=False,
            notes="valid_ru"
        ))

    return tests

def generate_edge_cases() -> List[TestCase]:
    """Generate edge case tests."""
    tests = []

    edge_cases = [
        # Single character (ambiguous)
        ("q", "й", True),
        ("a", "ф", True),

        # Very short words
        ("yt", "не", True),
        ("lf", "да", True),

        # Words that look similar in both layouts
        ("tot", "ещв", False),  # "tot" is valid EN

        # Special Russian letters
        ("~", "ё", True),  # Tilde -> Yo

        # Empty and whitespace
        ("", "", False),
        ("   ", "   ", False),

        # Only numbers
        ("123", "123", False),
        ("2024", "2024", False),

        # Only punctuation
        ("...", "...", False),
        ("???", ",,,", True),  # ? -> , in RU

        # Mixed valid
        ("Hello привет", "Hello привет", False),  # Both parts valid
    ]

    for i, (inp, exp, should_conv) in enumerate(edge_cases):
        tests.append(TestCase(
            id=f"edge_{i:04d}",
            category="edge_cases",
            input=inp,
            expected=exp,
            should_convert=should_conv,
            notes="edge"
        ))

    return tests

def generate_sentences_ru() -> List[TestCase]:
    """Generate Russian sentence tests."""
    tests = []

    # Common Russian sentences (will be corrupted)
    sentences = [
        "Привет как дела",
        "Спасибо за помощь",
        "Пожалуйста подожди",
        "Мне нужна помощь",
        "Где находится офис",
        "Когда будет готово",
        "Сколько это стоит",
        "Можно вопрос",
        "Не понимаю",
        "Повтори пожалуйста",
        "Хорошо договорились",
        "До завтра",
        "Увидимся позже",
        "Перезвони мне",
        "Напиши сообщение",
    ]

    for i, sentence in enumerate(sentences):
        corrupted = corrupt_ru_word(sentence)
        if corrupted != sentence:
            tests.append(TestCase(
                id=f"sentence_ru_{i:04d}",
                category="sentences_ru",
                input=corrupted,
                expected=sentence,
                should_convert=True
            ))

    return tests

def generate_sentences_en() -> List[TestCase]:
    """Generate English sentence tests (typed with RU layout)."""
    tests = []

    sentences = [
        "Hello how are you",
        "Thank you for help",
        "Please wait",
        "I need help",
        "Where is office",
        "When will ready",
        "How much cost",
        "Can I ask",
        "Do not understand",
        "Repeat please",
        "Ok deal",
        "See you tomorrow",
        "Call me back",
        "Send message",
        "Good job",
    ]

    for i, sentence in enumerate(sentences):
        corrupted = corrupt_en_word(sentence)
        if corrupted != sentence:
            tests.append(TestCase(
                id=f"sentence_en_{i:04d}",
                category="sentences_en",
                input=corrupted,
                expected=sentence,
                should_convert=True
            ))

    return tests


# MARK: - Main Generator

def generate_all_tests() -> List[TestCase]:
    """Generate all test cases."""
    all_tests = []

    generators = [
        ("Russian common words", generate_ru_common_words),
        ("English common words", generate_en_common_words),
        ("Tech buzzwords", generate_tech_buzzwords),
        ("Companies & services", generate_companies_services),
        ("Short words", generate_short_words),
        ("Shifted symbols", generate_shifted_symbols),
        ("Code switching", generate_code_switching),
        ("Sensitive data", generate_sensitive_data),
        ("CLI commands", generate_cli_commands),
        ("File paths", generate_file_paths),
        ("CamelCase/snake_case", generate_camelcase_snake),
        ("Uppercase", generate_uppercase),
        ("Punctuation", generate_punctuation),
        ("Numbers mixed", generate_numbers_mixed),
        ("Stress tests", generate_stress_tests),
        ("Edge cases", generate_edge_cases),
        ("Russian sentences", generate_sentences_ru),
        ("English sentences", generate_sentences_en),
    ]

    for name, generator in generators:
        tests = generator()
        print(f"  {name}: {len(tests)} tests")
        all_tests.extend(tests)

    return all_tests

def deduplicate_tests(tests: List[TestCase]) -> List[TestCase]:
    """Remove duplicate tests based on (input, expected) pair."""
    seen = set()
    unique = []

    for test in tests:
        key = (test.input, test.expected)
        if key not in seen:
            seen.add(key)
            unique.append(test)

    return unique

def main():
    print("=" * 60)
    print("TextSwitcher Test Generator v2.0")
    print("=" * 60)
    print()

    print("Generating tests...")
    all_tests = generate_all_tests()
    print()

    print(f"Total before dedup: {len(all_tests)}")
    unique_tests = deduplicate_tests(all_tests)
    print(f"Total after dedup: {len(unique_tests)}")
    print()

    # Convert to dict format
    output = [t.to_dict() for t in unique_tests]

    # Calculate stats
    should_convert = sum(1 for t in unique_tests if t.should_convert)
    should_not = len(unique_tests) - should_convert

    print("Statistics:")
    print(f"  Should convert: {should_convert} ({100*should_convert/len(unique_tests):.1f}%)")
    print(f"  Should NOT convert: {should_not} ({100*should_not/len(unique_tests):.1f}%)")
    print()

    # Count by category
    categories = {}
    for t in unique_tests:
        categories[t.category] = categories.get(t.category, 0) + 1

    print("By category:")
    for cat, count in sorted(categories.items()):
        print(f"  {cat}: {count}")
    print()

    # Save to file
    output_path = Path(__file__).parent.parent / "test_corpus_v2.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"Saved to: {output_path}")
    print(f"File size: {output_path.stat().st_size / 1024:.1f} KB")

if __name__ == "__main__":
    main()
