#!/usr/bin/env python3
"""Remove duplicate 'final c = TgThemeColors.of(context)' lines.
The script may have added duplicates right after existing ones."""
import re

root = '/home/ruslan/projects/STEALTH/client/lib'
filepath = None  # will be set by find

import os
for dirpath, dirnames, filenames in os.walk(root):
    if 'apple_liquid' in dirpath:
        continue
    for fn in filenames:
        if not fn.endswith('.dart') or fn.endswith('_test.dart'):
            continue
        filepath = os.path.join(dirpath, fn)
        with open(filepath, 'r') as f:
            content = f.read()
        
        original = content
        # Remove consecutive duplicate 'final c = TgThemeColors.of(context);' lines
        content = re.sub(
            r'(final c = TgThemeColors\.of\(context\);\s*\n)\s*final c = TgThemeColors\.of\(context\);',
            r'\1',
            content
        )
        # Also handle cases with just whitespace between
        content = re.sub(
            r'(final c = TgThemeColors\.of\(context\);\n)(\s*final c = TgThemeColors\.of\(context\);)',
            r'\1',
            content
        )
        
        if content != original:
            with open(filepath, 'w') as f:
                f.write(content)
            print(f"Fixed: {filepath}")
