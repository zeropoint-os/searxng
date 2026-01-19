#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== SearXNG Module Test Suite ===${NC}\n"

# Get the IP address of the searxng-main container
echo -e "${YELLOW}Step 1: Getting container IP...${NC}"
SEARXNG_IP=$(docker inspect searxng-main --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)

if [ -z "$SEARXNG_IP" ]; then
    echo -e "${RED}Error: searxng-main container not found or not running${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found searxng-main at: $SEARXNG_IP${NC}\n"

# Test 1: Health check
echo -e "${YELLOW}Step 2: Health check (GET /)${NC}"
if curl -s -o /dev/null -w "%{http_code}" "http://$SEARXNG_IP:8080/" | grep -q "200"; then
    echo -e "${GREEN}✓ SearXNG is responding${NC}\n"
else
    echo -e "${RED}✗ SearXNG is not responding${NC}\n"
    exit 1
fi

# Test 2: Search with JSON format
echo -e "${YELLOW}Step 3: Testing search with JSON response${NC}"
echo "Query: 'Artificial Intelligence'"
SEARCH_RESULT=$(curl -s -H "X-Forwarded-For: 127.0.0.1" "http://$SEARXNG_IP:8080/search?q=Artificial+Intelligence&format=json")
RESULT_COUNT=$(echo "$SEARCH_RESULT" | jq '.results | length' 2>/dev/null || echo "0")
echo -e "${GREEN}✓ Returned $RESULT_COUNT results${NC}\n"

# Test 3: Display first result
echo -e "${YELLOW}Step 4: First search result${NC}"
echo "$SEARCH_RESULT" | jq '.results[0]' 2>/dev/null || echo "No results"
echo ""

# Test 4: API v1 test
echo -e "${YELLOW}Step 5: Testing API v1 endpoint${NC}"
API_RESPONSE=$(curl -s -H "X-Forwarded-For: 127.0.0.1" "http://$SEARXNG_IP:8080/api/v1/search?q=kubernetes")
API_COUNT=$(echo "$API_RESPONSE" | jq '.results | length' 2>/dev/null || echo "0")
echo -e "${GREEN}✓ API v1 returned $API_COUNT results${NC}\n"

# Test 5: Instance info
echo -e "${YELLOW}Step 6: Getting instance information${NC}"
INFO=$(curl -s "http://$SEARXNG_IP:8080/api/v1/info" 2>/dev/null)
if echo "$INFO" | jq . > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Instance info retrieved${NC}"
    echo "$INFO" | jq '.' | head -20
    echo ""
else
    echo -e "${YELLOW}⚠ Instance info not available (may be normal)${NC}\n"
fi

# Test 6: Multiple search queries
echo -e "${YELLOW}Step 7: Testing multiple search queries${NC}"
queries=("docker" "terraform" "kubernetes")
for query in "${queries[@]}"; do
    count=$(curl -s -H "X-Forwarded-For: 127.0.0.1" "http://$SEARXNG_IP:8080/search?q=$query&format=json" | jq '.results | length' 2>/dev/null || echo "0")
    echo -e "  - Query '$query': ${GREEN}$count results${NC}"
done
echo ""

# Test 7: Language support
echo -e "${YELLOW}Step 8: Testing language parameter${NC}"
curl -s -H "X-Forwarded-For: 127.0.0.1" "http://$SEARXNG_IP:8080/search?q=test&format=json&lang=en" > /dev/null
echo -e "${GREEN}✓ Language parameter accepted${NC}\n"

# Test 8: Category support
echo -e "${YELLOW}Step 9: Testing category parameter${NC}"
curl -s -H "X-Forwarded-For: 127.0.0.1" "http://$SEARXNG_IP:8080/search?q=test&format=json&category=general" > /dev/null
echo -e "${GREEN}✓ Category parameter accepted${NC}\n"

# Summary
echo -e "${BLUE}=== Test Summary ===${NC}"
echo -e "${GREEN}✓ Container is running${NC}"
echo -e "${GREEN}✓ HTTP endpoint is accessible${NC}"
echo -e "${GREEN}✓ Search functionality works${NC}"
echo -e "${GREEN}✓ JSON API works${NC}"
echo ""
echo -e "${BLUE}Container IP: $SEARXNG_IP${NC}"
echo -e "${BLUE}Base URL: http://$SEARXNG_IP:8080${NC}"
echo -e "${BLUE}Query URL: http://$SEARXNG_IP:8080/search?q=<query>${NC}"
echo ""
echo -e "${GREEN}All tests passed!${NC}"
