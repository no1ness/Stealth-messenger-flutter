#!/usr/bin/env python3
"""Remove duplicate 'final c = TgThemeColors.of(context)' lines."""
import os
import re

root = '/home/ruslan/projects/STEALTH/client/lib'
for dirpath, dirnames, filenames in os.walk(root):
    if 'apple_liquid' in dirpath or '/tg/' in dirpath:
        continue
    for fn in filenames:
        if not fn.endswith('.dart') or fn.endswith('_test.dart'):
            continue
        filepath = os.path.join(dirpath, fn)
        with open(filepath, 'r') as f:
            content = f.read()
        
        original = content
        # Remove all but the first 'final c = TgThemeColors.of(context);' in each file
        # Count occurrences
        pattern = 'final c = TgThemeColors.of(context);'
        count = content.count(pattern)
        if count > 1:
            # Keep the first one, remove the rest
            lines = content.split('\n')
            found_first = False
            new_lines = []
            for line in lines:
                if pattern in line and not found_first:
                    found_first = True
                    new_lines.append(line)
                elif pattern in line:
                    # Skip this line (remove duplicate)
                    continue
                else:
                    new_lines.append(line)
            content = '\n'.join(new_lines)
        
        if content != original:
            with open(filepath, 'w') as f:
                f.write(content)
            print(f"Fixed duplicates: {filepath}")
