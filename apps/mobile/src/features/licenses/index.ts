import type { BundledLicense, LicensesData } from './licenses.generated';

export type { BundledLicense };

let cache: LicensesData | undefined;

/**
 * Loads the generated notices on first use. The table is a few hundred KB, so
 * importing it eagerly would cost every cold start for a screen most launches
 * never open.
 */
export function bundledLicenses(): LicensesData {
  if (!cache)
    cache = (
      require('./licenses.generated') as { bundledLicenses: LicensesData }
    ).bundledLicenses;
  return cache;
}

export function licenseEntry(name: string) {
  return bundledLicenses().packages.find((entry) => entry.name === name);
}

export function licenseText(entry: BundledLicense) {
  return bundledLicenses().texts[entry.text] ?? '';
}
