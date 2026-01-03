#!/bin/bash
# Demo script for the game tape location loader
# Shows TC08 device I/O working to load and display random locations

cd "$(dirname "$0")/.."

echo "========================================="
echo "Game Location Tape Demo"
echo "========================================="
echo ""
echo "This demo loads random location names from a TU56 DECtape"
echo "using the TC08 controller device (0o20)."
echo ""

# Create test script
cat > /tmp/game_demo.txt << 'EOF'
tc0 attach media/game.tu56
tc status
asm sd/gametest.asm 100
go 100
go 100
go 100
exit
EOF

echo "Running snova emulator..."
echo ""
OUTPUT=$(dotnet run --quiet --project snova/Snova.csproj < /tmp/game_demo.txt 2>&1)

echo "$OUTPUT" | sed -n '/^snova> TC0: attached media/s/^snova> //p' | head -1
echo "$OUTPUT" | sed -n '/^snova> Assembled/s/^snova> //p'
echo ""
echo "Locations displayed:"
echo "$OUTPUT" | grep "^snova> [A-Z]" | grep -v "Assembled\|TC0\|TC1" | sed 's/^snova> /  - /'
echo ""

echo ""
echo "========================================="
echo "The program:"
echo "  1. Uses RTC (0o21) to get random value"
echo "  2. Masks to 0-63 range"
echo "  3. Loads block from TC08 drive 0"
echo "  4. Prints the location name"
echo "========================================="

rm -f /tmp/game_demo.txt
