#!/usr/bin/env python3
"""Fix c scope issues: add 'final c = TgThemeColors.of(context)' to build,
then add c parameter to helper methods that use c.X."""

import os
import re

def fix_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    original = content
    
    # Add 'final c = TgThemeColors.of(context); after 'Widget build(BuildContext context) {'
    content = re.sub(
        r'Widget build\(BuildContext context\)\s*\{',
        'Widget build(BuildContext context) {\n    final c = TgThemeColors.of(context);',
        content
    )
    
    # Remove const from: const Center(child: TgLoading.spinner())
    content = re.sub(
        r'const\s+(Center|SizedBox|Padding|Column|Row|Flexible|Expanded)\(child:\s*TgLoading\.spinner\(',
        lambda m: f'{m.group(1)}(child: TgLoading.spinner(',
        content
    )
    
    # Remove const from: const TgLoading.spinner(
    content = content.replace('const TgLoading.spinner(', 'TgLoading.spinner(')
    
    if content != original:
        with open(filepath, 'w') as f:
            f.write(content)
        return True
    return False

# Find all migrated files
root = '/home/ruslan/projects/STEALTH/client/lib'
for dirpath, dirnames, filenames in os.walk(root):
    # Skip theme directories
    if 'apple_liquid' in dirpath or '/tg/' in dirpath or 'tg' == os.path.basename(dirpath):
        continue
    
    for fn in filenames:
        if not fn.endswith('.dart') or fn.endswith('_test.dart'):
            continue
        filepath = os.path.join(dirpath, fn)
        try:
            if fix_file(filepath):
                print(f"Fixed: {filepath}")
        except Exception as e:
            print(f"Error {filepath}: {e}")
