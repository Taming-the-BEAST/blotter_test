#!/usr/bin/env python3
import yaml
import re
import os
import sys
import shutil
import urllib.request
import xml.etree.ElementTree as ET
from typing import Dict, List, Any, Optional


# CBAN package files in order from oldest to newest
CBAN_VERSIONS = [
    ('2.1', 'packages2.1.xml'),
    ('2.1.3', 'packages2.1.3.xml'),
    ('2.2.0', 'packages2.2.0.xml'),
    ('2.2.1', 'packages2.2.1.xml'),
    ('2.3.0', 'packages2.3.0.xml'),
    ('2.3.1', 'packages2.3.1.xml'),
    ('2.5', 'packages2.5.xml'),
    ('2.6', 'packages2.6.xml'),
    ('2.7', 'packages2.7.xml'),
]

CBAN_BASE_URL = 'https://raw.githubusercontent.com/CompEvol/CBAN/master/'


class CBANLookup:
    """Looks up package compatibility from CBAN repository."""

    def __init__(self):
        self._cache: Dict[str, set] = {}  # version -> set of package names
        self._loaded = False

    def _load_cban_data(self):
        """Load package data from CBAN (lazy loading)."""
        if self._loaded:
            return

        print('Fetching package compatibility from CBAN...')

        for version, filename in CBAN_VERSIONS:
            try:
                url = CBAN_BASE_URL + filename
                with urllib.request.urlopen(url, timeout=10) as response:
                    xml_content = response.read()
                    root = ET.fromstring(xml_content)

                    packages = set()
                    for pkg in root.findall('.//package'):
                        name = pkg.get('name')
                        if name:
                            packages.add(name)

                    self._cache[version] = packages

            except Exception as e:
                print(f'  Warning: Could not fetch {filename}: {e}')
                self._cache[version] = set()

        self._loaded = True
        print('  Done.')

    def get_latest_beast_version(self, packages: List[str]) -> Optional[str]:
        """
        Find the most recent BEAST2 version that supports all given packages.

        Args:
            packages: List of package names to check

        Returns:
            Most recent BEAST version string, or None if no packages or not found
        """
        if not packages:
            return None

        self._load_cban_data()

        # Check from newest to oldest
        for version, _ in reversed(CBAN_VERSIONS):
            cban_packages = self._cache.get(version, set())

            # Check if any of the tutorial's packages are in this BEAST version
            for pkg in packages:
                if pkg in cban_packages:
                    return version

        return None


class TutorialMigrator:
    """Migrates tutorial metadata by analyzing content and suggesting new fields."""

    def __init__(self):
        self.cban = CBANLookup()

    def analyze_content(self, text: str) -> Dict[str, Any]:
        """Analyze tutorial content and suggest metadata."""
        text_lower = text.lower()

        return {
            'keywords': self.detect_keywords(text_lower),
            'packages': self.detect_packages(text_lower),
            'tutorial_type': self.detect_type(text_lower),
            'domains': self.detect_domains(text_lower)
        }

    def detect_keywords(self, text: str) -> List[str]:
        """Detect keywords from tutorial content."""
        keywords = []

        patterns = {
            'coalescent': r'coalescent',
            'birth-death': r'birth.?death',
            'molecular clock': r'molecular clock',
            'calibration': r'calibrat',
            'phylogeography': r'phylogeograph',
            'structured population': r'structured|population structure',
            'skyline': r'skyline',
            'migration': r'migration',
            'Bayesian inference': r'bayesian'
        }

        for keyword, pattern in patterns.items():
            if re.search(pattern, text):
                keywords.append(keyword)

        return keywords[:8]  # Take first 8

    def detect_packages(self, text: str) -> List[str]:
        """Detect BEAST2 packages from tutorial content."""
        packages = []

        patterns = {
            'BDSKY': r'bdsky|birth.?death skyline',
            'MASCOT': r'mascot',
            'MultiTypeTree': r'multitypetree|mtt',
            'StarBeast3': r'starbeast3',
            'StarBeast2': r'starbeast2',
            'StarBeast': r'starbeast(?!2|3)',
            'SCOTTI': r'scotti',
            'SA': r'sampled ancestor'
        }

        for package, pattern in patterns.items():
            if re.search(pattern, text):
                packages.append(package)

        return packages

    def detect_type(self, text: str) -> str:
        """Detect tutorial type from content."""
        if re.search(r'introduction|getting started|basic', text):
            return 'Core'
        if re.search(r'case study|application', text):
            return 'Applied'
        return 'Model set-up'

    def detect_domains(self, text: str) -> List[str]:
        """Detect application domains from content."""
        domains = []

        patterns = {
            'virology': r'virus|viral|influenza',
            'epidemiology': r'epidem|outbreak|transmission',
            'phylogeography': r'phylogeograph|geographic',
            'speciation': r'speciation|species tree'
        }

        for domain, pattern in patterns.items():
            if re.search(pattern, text):
                domains.append(domain)

        return domains if domains else ['general']

    def migrate(self, readme_path: str) -> Dict[str, Any]:
        """Migrate tutorial metadata from README file."""
        try:
            with open(readme_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except FileNotFoundError:
            return {'error': f'File not found: {readme_path}'}
        except Exception as e:
            return {'error': f'Error reading file: {str(e)}'}

        # Extract frontmatter
        match = re.match(r'\A---\s*\n(.*?)\n---\s*\n', content, re.DOTALL)
        if not match:
            return {'error': 'No frontmatter found'}

        frontmatter_text = match.group(1)
        rest = content[match.end():]

        try:
            existing = yaml.safe_load(frontmatter_text)
            if existing is None:
                existing = {}
        except yaml.YAMLError as e:
            return {'error': f'Invalid YAML in frontmatter: {str(e)}'}

        # Analyze content and generate suggestions
        suggestions = self.analyze_content(content)

        # Merge with existing, new fields take precedence if not already set
        updated = existing.copy()

        # Rename beastversion -> beastversion_tutorial if it exists
        if 'beastversion' in updated and 'beastversion_tutorial' not in updated:
            updated['beastversion_tutorial'] = updated.pop('beastversion')

        # Get packages (from suggestions or existing)
        packages = suggestions['packages'] or updated.get('packages', [])

        # Look up beastversion_package from CBAN
        beastversion_package = self.cban.get_latest_beast_version(packages)

        updated.update({
            'keywords': suggestions['keywords'],
            'packages': suggestions['packages'],
            'tutorial_type': suggestions['tutorial_type'],
            'status': 'current',
            'domains': suggestions['domains']
        })

        # Add beastversion_package if found
        if beastversion_package:
            updated['beastversion_package'] = beastversion_package

        return {
            'existing': existing,
            'suggested': suggestions,
            'updated': updated,
            'content': rest,
            'beastversion_package': beastversion_package
        }

    def write_updated(self, readme_path: str, frontmatter: Dict[str, Any], content: str):
        """Write updated frontmatter and content back to README."""
        # Create backup
        backup_path = f'{readme_path}.backup'
        shutil.copy2(readme_path, backup_path)

        # Write updated file
        with open(readme_path, 'w', encoding='utf-8') as f:
            f.write('---\n')
            yaml.dump(frontmatter, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
            f.write('---\n')
            f.write(content)


def main():
    """Main entry point for command-line usage."""
    if len(sys.argv) < 2:
        print('Usage: migrate_tutorial.py TUTORIAL_DIR')
        sys.exit(1)

    tutorial_dir = sys.argv[1]
    readme_path = os.path.join(tutorial_dir, 'README.md')

    if not os.path.exists(readme_path):
        print(f'Error: {readme_path} not found')
        sys.exit(1)

    migrator = TutorialMigrator()
    result = migrator.migrate(readme_path)

    if 'error' in result:
        print(f'Error: {result["error"]}')
        sys.exit(1)

    print('\n' + '=' * 70)
    print(f'Tutorial: {tutorial_dir}')
    print('=' * 70)

    print('\nSuggested metadata:')
    print(yaml.dump(result['suggested'], default_flow_style=False, sort_keys=False))

    if result.get('beastversion_package'):
        print(f'CBAN lookup: packages supported in BEAST {result["beastversion_package"]}')

    print('\nUpdated frontmatter:')
    print(yaml.dump(result['updated'], default_flow_style=False, sort_keys=False))

    response = input('\nApply changes? (y/n): ').strip().lower()

    if response == 'y':
        migrator.write_updated(readme_path, result['updated'], result['content'])
        print(f'✓ Updated {readme_path}')
        print(f'  Backup: {readme_path}.backup')
    else:
        print('No changes applied')


if __name__ == '__main__':
    main()
