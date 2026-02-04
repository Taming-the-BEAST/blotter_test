#!/bin/bash

# List of tutorial repositories
TUTORIALS=(
  # "Introduction-to-BEAST2"
  "Structured-coalescent"
  "Skyline-plots"
  # "MEP-tutorial"
  # "StarBeast-Tutorial"
  # "Substitution-model-averaging"
  # Add all other tutorials...
)

TUTORIAL_DIR="/tmp/tutorials"
mkdir -p "$TUTORIAL_DIR"

echo "Cloning and migrating tutorials..."
echo "=================================="

for tutorial in "${TUTORIALS[@]}"; do
  echo ""
  echo "Processing: $tutorial"
  echo "---"
  
  # Clone if not exists
  if [ ! -d "$TUTORIAL_DIR/$tutorial" ]; then
    git clone "https://github.com/taming-the-beast/$tutorial.git" "$TUTORIAL_DIR/$tutorial"
  fi
  
  # Run migration
  python3 _scripts/migrate_tutorial.py "$TUTORIAL_DIR/$tutorial"
  
  echo ""
done

echo ""
echo "=================================="
echo "Migration complete!"
echo "Review changes in: $TUTORIAL_DIR"
