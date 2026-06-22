#!/usr/bin/env python3
"""Fix c scope issues in helper methods by inlining TgThemeColors.of(context).X"""
import os
import re

root = '/home/ruslan/projects/STEALTH/client/lib'

def fix_c_inline(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    original = content
    
    # Pattern: c.SOMETHING -> TgThemeColors.of(context).SOMETHING
    # But only if 'final c = TgThemeColors' is NOT defined in the file
    if 'final c = TgThemeColors.of(context)' in content:
        # c is defined, so we need to find which methods don't have it
        # and replace c.X with TgThemeColors.of(context).X in those methods
        
        # Split into methods by looking for function definitions
        # This is a heuristic approach
        lines = content.split('\n')
        new_lines = []
        in_method_without_c = False
        brace_depth = 0
        method_start = -1
        
        i = 0
        while i < len(lines):
            line = lines[i]
            stripped = line.strip()
            
            # Detect method start (a line ending with '{' that's a method declaration)
            if re.match(r'^\s+\w+\s+\(', stripped) and stripped.endswith('{'):
                # Check if this method starts with 'Widget build' (already has c)
                if not stripped.startswith('Widget build') or True:  # for now check all
                    method_start = i
                    in_method_without_c = True
                    brace_depth = 1
            
            if in_method_without_c:
                # Count braces
                brace_depth += stripped.count('{') - stripped.count('}')
                if brace_depth <= 0:
                    in_method_without_c = False
                    method_start = -1
            
            i += 1
        
        # Simpler approach: just check if the file has a pattern that suggests
        # c.X is used outside of build methods - replace all c.X with
        # TgtThemeColors.of(context).X where c is not defined
        pass
    
    # Simpler: just replace all c.X that are NOT in lines containing 'final c '
    # Actually the simplest: just replace ALL c.X inline in lines where c is NOT defined
    # Let me just do this:
    
    lines = content.split('\n')
    new_lines = []
    has_c_definition = False
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        
        # Track if we're in a scope with c defined
        if 'final c = TgThemeColors.of(context)' in stripped:
            has_c_definition = True
        
        # If we find c.X on a line, check if it's a c definition line already
        if re.search(r'\bc\.\w+', stripped):
            if 'final c =' in stripped:
                # This IS the definition, leave it
                new_lines.append(line)
            elif not has_c_definition:
                # c is not defined in scope, need to inline
                # But we can't easily determine scope from here
                new_lines.append(line.replace('c.', 'TgThemeColors.of(context).'))
                print(f"  Inline c at {filepath}:{i+1}")
            else:
                new_lines.append(line)
        else:
            new_lines.append(line)
        
        # If we exit a build method (by finding another method), reset
        if stripped.startswith('Widget ') and 'build' in stripped:
            # build method just started, c is defined next
            pass
    
    # Actually this approach is too simplistic. Let me be smarter.
    # For each file, find each method that's not build() and contains c.X,
    # then add 'final c = TgtThemeColors.of(context)' inside it.
    
    if content != original:
        with open(filepath, 'w') as f:
            f.write(content)
        return True
    return False

# Walk files
for dirpath, dirnames, filenames in os.walk(root):
    if 'apple_liquid' in dirpath:
        continue
    for fn in filenames:
        if not fn.endswith('.dart') or fn.endswith('_test.dart'):
            continue
        filepath = os.path.join(dirpath, fn)
        try:
            fix_c_inline(filepath)
        except Exception as e:
            print(f"Error {filepath}: {e}")

print("Done")
