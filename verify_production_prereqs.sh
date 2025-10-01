#!/usr/bin/env bash
set -eo pipefail

echo "=== Production Environment Prerequisites Check ==="
echo

# Check promtool (CRITICAL - required for ETL)
echo "1. Checking promtool..."
if command -v promtool >/dev/null; then
    echo "✅ promtool found: $(promtool --version)"
else
    echo "❌ promtool NOT FOUND - Install with: brew install prometheus"
    exit 1
fi
echo

# Check jq
echo "2. Checking jq..."
if command -v jq >/dev/null; then
    echo "✅ jq found: $(jq --version)"
else
    echo "❌ jq NOT FOUND - Install with: brew install jq"
    exit 1
fi
echo

# Check psql
echo "3. Checking PostgreSQL client..."
if command -v psql >/dev/null; then
    echo "✅ psql found: $(psql --version)"
else
    echo "❌ psql NOT FOUND - Install PostgreSQL client"
    exit 1
fi
echo

# Check date command compatibility (GNU vs BSD)
echo "4. Checking date command..."
if date --date="@1640995200" -u +"%Y-%m-%dT%H:%M:%SZ" >/dev/null 2>&1; then
    echo "✅ GNU date found (compatible with scripts)"
else
    echo "⚠️  BSD date detected - scripts may need adjustment"
    echo "   Test command: date --date=\"@1640995200\" -u +\"%Y-%m-%dT%H:%M:%SZ\""
fi
echo

# Check .env file exists
echo "5. Checking .env file..."
if [ -f ".env" ]; then
    echo "✅ .env file found"

    # Check critical environment variables
    echo "6. Checking environment variables..."
    source .env

    if [ -n "$PROMETHEUS_ENDPOINT" ]; then
        echo "✅ PROMETHEUS_ENDPOINT is set"
    else
        echo "❌ PROMETHEUS_ENDPOINT not set in .env"
        exit 1
    fi

    if [ -n "$POSTGRES_CONNECTION_STRING" ]; then
        echo "✅ POSTGRES_CONNECTION_STRING is set"
    else
        echo "❌ POSTGRES_CONNECTION_STRING not set in .env"
        exit 1
    fi
else
    echo "❌ .env file not found - create from .env.example"
    exit 1
fi
echo

# Check PostgreSQL connectivity
echo "7. Testing PostgreSQL connection..."
if psql "$POSTGRES_CONNECTION_STRING" -c "SELECT 1;" >/dev/null 2>&1; then
    echo "✅ PostgreSQL connection successful"
else
    echo "❌ PostgreSQL connection failed"
    exit 1
fi
echo

# Check Prometheus connectivity (basic)
echo "8. Testing Prometheus endpoint connectivity..."
if command -v curl >/dev/null; then
    # Extract base URL from PROMETHEUS_ENDPOINT for connectivity test
    BASE_URL=$(echo "$PROMETHEUS_ENDPOINT" | sed 's|/api/.*||')
    if curl -s --connect-timeout 10 "$BASE_URL" >/dev/null; then
        echo "✅ Prometheus endpoint reachable"
    else
        echo "⚠️  Prometheus endpoint connection issue (may be normal with auth)"
    fi
else
    echo "⚠️  curl not available - skipping Prometheus connectivity test"
fi
echo

echo "=== Prerequisites Check Complete ==="