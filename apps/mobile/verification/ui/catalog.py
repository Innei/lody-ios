"""Production copy for assertions, read from the same catalog the app ships."""
import json
import os
import re
from pathlib import Path

LANGUAGE = os.environ.get('LODY_UI_LANGUAGE', 'en')
CATALOG = json.loads(
    (Path(__file__).resolve().parents[2] / 'locales' / f'{LANGUAGE}.json').read_text()
)


def text(key, **variables):
    template = CATALOG[key]
    return re.sub(r'\{([A-Za-z][A-Za-z0-9_]*)\}',
                  lambda match: str(variables.get(match.group(1), match.group(0))),
                  template)


def plural(key, count, **variables):
    category = 'one' if LANGUAGE == 'en' and count == 1 else 'other'
    return text(f'{key}.{category}', count=count, **variables)
