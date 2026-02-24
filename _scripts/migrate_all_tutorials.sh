#!/bin/bash

# List of tutorial repositories
TUTORIALS=(
  # "Introduction-to-BEAST2"
  # "Structured-coalescent"
  # "Skyline-plots"
  # "MEP-tutorial"
  # "StarBeast-Tutorial"
  # "Substitution-model-averaging"
  # StarBeast-Tutorial
  StarBeast3-Tutorial
  # Add all other tutorials...
)

TUTORIAL_DIR="/tmp/tutorials"
SCRIPT_PATH="$0"

mkdir -p "$TUTORIAL_DIR"

echo "Cloning and migrating tutorials..."
echo "=================================="
echo ""

# Ask once at the beginning
read -p "Mark tutorials as done after processing? (y/yes/n/no): " mark_done_choice

case "$mark_done_choice" in
  y|Y|yes|Yes|YES)
    MARK_DONE=true
    echo "-> Tutorials will be commented out in this script after processing."
    ;;
  *)
    MARK_DONE=false
    echo "-> Tutorials will NOT be marked as done. You can re-run this script to process them again."
    ;;
esac

echo ""

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

  # Mark as done if user chose to do so
  if [ "$MARK_DONE" = true ]; then
    # Comment out this tutorial in the script (escape special chars in tutorial name)
    escaped_tutorial=$(echo "$tutorial" | sed 's/[[\.*^$()+?{|]/\\&/g')
    sed -i.bak "s/^  \"${escaped_tutorial}\"$/  # \"${escaped_tutorial}\" # DONE/" "$SCRIPT_PATH"
    echo "✓ Marked '$tutorial' as done"
  fi

  echo ""
done

echo ""
echo "=================================="
echo "Migration complete!"
echo "Review changes in: $TUTORIAL_DIR"

if [ "$MARK_DONE" = true ]; then
  echo ""
  echo "Processed tutorials have been commented out in this script."
  echo "To process them again, uncomment them in: $SCRIPT_PATH"
fi
