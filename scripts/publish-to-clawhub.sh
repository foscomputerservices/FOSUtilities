#!/bin/bash
# Publish FOSMVVM skills to ClawHub
# Requires: npm install -g clawhub && clawhub login

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SKILLS_DIR="$REPO_ROOT/.claude/skills"

VERSION="${1:?Usage: publish-to-clawhub.sh <version> [changelog]}"
CHANGELOG="${2:-"Release $VERSION"}"

SKILLS=(
    "fosmvvm-viewmodel-generator:FOSMVVM ViewModel Generator"
    "fosmvvm-fields-generator:FOSMVVM Fields Generator"
    "fosmvvm-serverrequest-generator:FOSMVVM ServerRequest Generator"
    "fosmvvm-fluent-datamodel-generator:FOSMVVM Fluent DataModel Generator"
    "fosmvvm-leaf-view-generator:FOSMVVM Leaf View Generator"
    "fosmvvm-swiftui-view-generator:FOSMVVM SwiftUI View Generator"
    "fosmvvm-react-view-generator:FOSMVVM React View Generator"
    "fosmvvm-serverrequest-test-generator:FOSMVVM ServerRequest Test Generator"
    "fosmvvm-viewmodel-test-generator:FOSMVVM ViewModel Test Generator"
    "fosmvvm-ui-tests-generator:FOSMVVM UI Tests Generator"
    "fosmvvm-swiftui-app-setup:FOSMVVM SwiftUI App Setup"
)

for entry in "${SKILLS[@]}"; do
    slug="${entry%%:*}"
    name="${entry#*:}"
    echo "Publishing $name ($slug) v$VERSION..."
    clawhub publish "$SKILLS_DIR/$slug" \
        --slug "$slug" \
        --name "$name" \
        --version "$VERSION" \
        --changelog "$CHANGELOG"
    echo "  Published $slug"
done

echo ""
echo "All skills published to ClawHub v$VERSION"
