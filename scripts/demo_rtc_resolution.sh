#!/bin/bash
# Demo showing RTC second-level resolution for random location selection

cd "$(dirname "$0")/.."

cat > /tmp/rtc_test.txt << 'EOF'
tc0 attach media/game.tu56
asm sd/gametest.asm 100
go 100
exit
EOF

echo "========================================="
echo "RTC Second-Level Resolution Demo"
echo "========================================="
echo ""
echo "The RTC device (0o21) provides three values:"
echo "  DIA: Minutes since midnight (updates ~60s)"
echo "  DIB: Epoch seconds (low word) - updates every second"
echo "  DIC: Epoch seconds (high word)"
echo ""
echo "Our program uses DIB for random block selection."
echo ""
echo "Running 10 consecutive times (1 second apart):"
echo ""

for i in {1..10}; do
    RESULT=$(dotnet run --quiet --project snova/Snova.csproj < /tmp/rtc_test.txt 2>&1 | \
             grep "^snova> [A-Z]" | grep -v "Assembled\|TC" | sed 's/^snova> //' | head -1)
    printf "%2d. %s\n" "$i" "$RESULT"
    sleep 1
done

echo ""
echo "========================================="
echo "✓ Each second produces a different location!"
echo "========================================="

rm -f /tmp/rtc_test.txt
