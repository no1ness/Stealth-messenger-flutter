#!/usr/bin/env python3
import os

root = 'ui/screens/dashboard'
filepath = os.path.join(root, 'dashboard_home_screen.dart')

with open(filepath, 'r') as f:
    content = f.read()

# Fix Color(x)Secondary patterns in build method context -> c.textSecondary
content = content.replace('Color(0xFFF5F5F5)Secondary', 'c.textSecondary')

# Fix _platformColor returns (no c in scope)
content = content.replace(
    'return c.textSecondary;',
    'return const Color(0xFF8E8E93);'
)

# Fix iconsize -> icon (typo from old code)
content = content.replace(
    'return Icon(iconsize, color: color);',
    'return Icon(icon, color: color);'
)

with open(filepath, 'w') as f:
    f.write(content)

print(f"Fixed {filepath}")
