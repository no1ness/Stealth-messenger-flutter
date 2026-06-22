#!/bin/bash
# Targeted fixes for known error patterns
cd /home/ruslan/projects/STEALTH/client/lib

echo "=== Fix mangled )Secondary patterns ==="
for f in $(grep -rl ')Secondary' . 2>/dev/null | grep -v 'themes/apple_liquid' | grep -v 'themes/tg' | grep -v '_test'); do
    # Replace patterns like Color(x)Secondary -> c.textSecondary
    sed -i 's/)Secondary/, color: c\.textSecondary/g' "$f"
    echo "  Fixed )Secondary: $f"
done

echo "=== Fix mangled )Muted patterns ==="
for f in $(grep -rl ')Muted' . 2>/dev/null | grep -v 'themes/apple_liquid' | grep -v 'themes/tg' | grep -v '_test'); do
    sed -i 's/)Muted/, color: c\.textMuted/g' "$f"
    echo "  Fixed )Muted: $f"
done

echo "=== Fix mangled )Primary patterns ==="
for f in $(grep -rl ')Primary' . 2>/dev/null | grep -v 'themes/apple_liquid' | grep -v 'themes/tg' | grep -v '_test'); do
    sed -i 's/)Primary/, color: c\.primary/g' "$f"
    echo "  Fixed )Primary: $f"
done

echo "=== Fix mangled )Tertiary patterns ==="
for f in $(grep -rl ')Tertiary' . 2>/dev/null | grep -v 'themes/apple_liquid' | grep -v 'themes/tg' | grep -v '_test'); do
    sed -i 's/)Tertiary/, color: c\.textTertiary/g' "$f"
    echo "  Fixed )Tertiary: $f"
done

echo "=== Fix remaining tgLoading.spinner with double-spinner ==="
for f in $(grep -rl 'TgLoading\.spinner\.spinner' . 2>/dev/null | grep -v 'themes/apple_liquid' | grep -v 'themes/tg'); do
    sed -i 's/TgLoading\.spinner\.spinner/TgLoading.spinner/g' "$f"
    echo "  Fixed double spinner: $f"
done

echo "=== Fix const SizedBox where args use non-const ==="
# These show up as const_with_non_constant_argument errors
# Remove const from any widget line that has .spacing. or .colors. or c. or TgSpacing
for f in $(grep -rl 'const.*SizedBox' . 2>/dev/null | grep -v 'themes/apple_liquid' | grep -v 'themes/tg' | grep -v '_test'); do
    # Only do this in files known to have issues
    if grep -qE 'const.*SizedBox.*(c\.|TgSpacing)' "$f" 2>/dev/null; then
        sed -i 's/const SizedBox(/SizedBox(/g' "$f"
        echo "  Fixed const SizedBox: $f"
    fi
done

echo "=== Fix const Column/Row/Text/etc where args use non-const ==="
for f in $(grep -rl 'const Column' . 2>/dev/null | grep -v 'themes/apple_liquid' | grep -v 'themes/tg' | grep -v '_test'); do
    sed -i 's/const Column(/Column(/g' "$f"
done
for f in $(grep -rl 'const Row' . 2>/dev/null | grep -v 'themes/apple_liquid' | grep -v 'themes/tg' | grep -v '_test'); do
    sed -i 's/const Row(/Row(/g' "$f"
done
echo "  Fixed common const widget wrapper"

echo "=== Fix iconSize in text styles (should be fontSize) ==="
for f in $(grep -rl 'iconSize:' . 2>/dev/null | grep -v 'themes/apple_liquid' | grep -v 'themes/tg' | grep -v '_test'); do
    sed -i 's/iconSize:/fontSize:/g' "$f"
    echo "  Fixed iconSize->fontSize: $f"
done

echo "=== Done ==="
