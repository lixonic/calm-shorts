#!/usr/bin/env python3
"""Expose a short tail of non-secret build/test output in GitHub annotations."""
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text(errors='replace')[-7000:] if p.exists() else 'Diagnostic log not created'
s = s.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
print('::error title=Build or native test diagnostic::' + s)
