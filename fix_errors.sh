#!/bin/bash
# Fix remaining errors in migrated files
cd /home/ruslan/projects/STEALTH/client/lib

echo "=== Fix 1: Remove const from const SizedBox/Tex/Row/Column/Icon/Padding/Container etc that use c., TgSpacing, TgTypography ==="
# This removes const from widget calls where any argument references c., TgSpacing, or TgTypography
for f in $(grep -rl 'const.*c\.' . 2>/dev/null | grep -v 'themes/apple_liquid' | grep -v 'themes/tg' | grep -v '_test'); do
    # Remove const keyword from lines containing 'const' followed by 'c.' in a constructor call
    sed -i 's/const SizedBox(width: c\./SizedBox(width: c\./g' "$f"
    sed -i 's/const SizedBox(height: c\./SizedBox(height: c\./g' "$f"
    sed -i 's/const Text(/Text(/g' "$f"
    sed -i 's/const Row(/Row(/g' "$f"
    sed -i 's/const Column(/Column(/g' "$f"
    sed -i 's/const Icon(/Icon(/g' "$f"
    sed -i 's/const Padding(/Padding(/g' "$f"
    sed -i 's/const Container(/Container(/g' "$f"
    sed -i 's/const Center(/Center(/g' "$f"
    sed -i 's/const Align(/Align(/g' "$f"
    sed -i 's/const Flexible(/Flexible(/g' "$f"
    sed -i 's/const Expanded(/Expanded(/g' "$f"
    sed -i 's/const ClipRRect(/ClipRRect(/g' "$f"
    sed -i 's/const Border(/Border(/g' "$f"
    sed -i 's/const BorderSide(/BorderSide(/g' "$f"
    sed -i 's/const EdgeInsets(/EdgeInsets(/g' "$f"
    sed -i 's/const RoundedRectangleBorder(/RoundedRectangleBorder(/g' "$f"
    sed -i 's/const BoxDecoration(/BoxDecoration(/g' "$f"
    echo "  Fixed consts: $f"
done

echo "=== Fix 2: Add 'final c' inside helper methods that use c.X but don't have it ==="
# Find files where c.X is used outside of build methods
# We'll look for methods (non-build) that use c. but have no c definition inside them

echo "=== Fix 3: TgLoading as widget: const TgLoading(size:...) -> TgLoading() (use .spinner()) ==="
for f in $(grep -rl 'TgLoading(' . 2>/dev/null | grep -v 'themes/apple_liquid' | grep -v 'themes/tg' | grep -v '_test'); do
    # Replace: const TgLoading(...) or TgLoading(size:..., strokeWidth:...) -> TgLoading.spinner()
    sed -i 's/const TgLoading(/TgLoading.spinner(/g' "$f"
    sed -i 's/\bTgLoading(/TgLoading.spinner(/g' "$f"
    # Remove size: and strokeWidth: params since spinner() doesn't have them
    sed -i 's/, size: [0-9]*//g' "$f"
    sed -i 's/, strokeWidth: [0-9]*//g' "$f"
    sed -i 's/size: [0-9]*, //g' "$f"
    sed -i 's/strokeWidth: [0-9]*, //g' "$f"
    echo "  Fixed TgLoading: $f"
done

echo "=== Fix 4: showStealthSnackBar -> TgSnackBar.show ==="
for f in $(grep -rl 'showStealthSnackBar' . 2>/dev/null | grep -v 'themes/apple_liquid'); do
    sed -i 's/showStealthSnackBar/TgSnackBar.show/g' "$f"
    echo "  Fixed: $f"
done

echo "=== Fix 5: showStealthDialog -> TgDialog.show ==="
for f in $(grep -rl 'showStealthDialog' . 2>/dev/null | grep -v 'themes/apple_liquid'); do
    sed -i 's/showStealthDialog/TgDialog.show/g' "$f"
    echo "  Fixed: $f"
done

echo "=== Fix 6: StealthHaptics -> TgHaptics ==="
for f in $(grep -rl 'StealthHaptics' . 2>/dev/null | grep -v 'themes/apple_liquid'); do
    sed -i 's/StealthHaptics/TgHaptics/g' "$f"
    sed -i 's/TgHaptics\.success/TgHaptics\.medium/g' "$f"
    sed -i 's/TgHaptics\.error/TgHaptics\.heavy/g' "$f"
    echo "  Fixed: $f"
done

echo "=== Fix 7: Old Stealth widgets -> Tg equivalents ==="
for f in $(grep -rl 'StealthBottomNavBar\b' . 2>/dev/null | grep -v 'themes/apple_liquid'); do
    sed -i 's/StealthBottomNavBar/TgBottomNavBar/g' "$f"
done
for f in $(grep -rl 'StealthSectionHeader\b' . 2>/dev/null | grep -v 'themes/apple_liquid'); do
    sed -i 's/StealthSectionHeader/TgSectionHeader/g' "$f"
done
for f in $(grep -rl 'StealthTextField\b' . 2>/dev/null | grep -v 'themes/apple_liquid'); do
    sed -i 's/StealthTextField/TgTextField/g' "$f"
done
for f in $(grep -rl 'StealthSearchField\b' . 2>/dev/null | grep -v 'themes/apple_liquid'); do
    sed -i 's/StealthSearchField/TgSearchField/g' "$f"
done
for f in $(grep -rl 'StealthMessageInput\b' . 2>/dev/null | grep -v 'themes/apple_liquid'); do
    sed -i 's/StealthMessageInput/TgMessageInput/g' "$f"
done
echo "  Fixed old Stealth widget names"

echo "=== Complete ==="
