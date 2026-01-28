#!/bin/bash
set -e
# Coverage script for Django projects with Docker Compose

# Ensure we're in the project root (where docker-compose.yml is located)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "🧪 Running tests with coverage..."

# Run tests with coverage
docker compose exec web coverage run manage.py test "$@"

echo "📊 Generating coverage reports..."

# Generate text report (suppress warnings about temporary files)
echo "Text report:"
docker compose exec web coverage report --ignore-errors 2>&1 | grep -v "CoverageWarning.*couldnt-parse" | grep -v "CoverageWarning.*no-source" || true

# Generate HTML report
docker compose exec web coverage html --ignore-errors 2>&1 | grep -v "CoverageWarning.*couldnt-parse" | grep -v "CoverageWarning.*no-source" || true

echo ""
echo "✅ Coverage reports generated!"
echo ""
echo "📈 View reports:"
echo "  Text report: docker compose exec web coverage report"
echo "  HTML report: Open htmlcov/index.html in browser"
echo ""
echo "🌐 Quick HTML server (optional):"
echo "  docker compose exec -d web python -m http.server 8001 -d htmlcov"
echo "  Open: http://localhost:8001"
echo ""
echo "🛑 Stop HTML server:"
echo "  docker compose exec web pkill -f 'python -m http.server 8001' || echo 'No server running'"