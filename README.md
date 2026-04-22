# nfe-xml-organizer

NF-e XML files from different companies and different issue months can easily accumulate in the same folder over time. Before those files are handed off for accounting work, they often need to be separated by CNPJ and month in a way that is consistent and easy to verify.

This PowerShell script handles that step by reading each XML, extracting the emitter or recipient CNPJ, determining the issue month, and then moving or copying the file into the expected folder structure.

The result is a deterministic organization rule based on document metadata instead of manual sorting.

```text
<CNPJ>/<YYYY-MM>/
```

It reads CNPJ data from the XML itself, uses the issue date when available, and only falls back to the access key in the file name when the month cannot be determined from the XML.

## Example

Before:

```text
mixed/
  41240312345678000123550010000001234567890123-nfe.xml
  41240412345678000123550010000001234567890124-nfe.xml
  35240555443322000199550010000004561234567890-nfe.xml
```

After:

```text
organized/
  12345678000123/
    2024-03/
      41240312345678000123550010000001234567890123-nfe.xml
    2024-04/
      41240412345678000123550010000001234567890124-nfe.xml
  55443322000199/
    2024-05/
      35240555443322000199550010000004561234567890-nfe.xml
```

## Why This Exists

This script came from a practical workflow problem.

XML files from different companies and different issue months had been accumulating in the same folder over time. Before they could be handed off for accounting work, they had to be separated by CNPJ and month.

Doing that manually created an obvious risk: placing XML files under the wrong company or the wrong period. This utility standardizes that step by using the document metadata to decide where each file belongs.

---

## Input Assumptions

- files are NF-e XML documents
- file names follow the common pattern:

```text
<44-digit-access-key>-nfe.xml
```

- the script first tries to read metadata from the XML itself
- if the issue month is missing from the XML, it falls back to the access key in the file name

---

## Output Structure

If grouping by emitter CNPJ:

```text
<output>/12345678000123/2024-03/
<output>/12345678000123/2024-04/
<output>/55443322000199/2024-05/
```

If grouping by recipient CNPJ:

```text
<output>/99887766000155/2024-03/
<output>/99887766000155/2024-05/
<output>/11222333000144/2024-04/
```

---

## Usage

Move files into the new structure:

```powershell
powershell -ExecutionPolicy Bypass -File .\organize-nfe-xml.ps1 `
  -SourceDirectory .\test-input `
  -OutputDirectory .\organized `
  -GroupBy emit
```

Copy files instead of moving:

```powershell
powershell -ExecutionPolicy Bypass -File .\organize-nfe-xml.ps1 `
  -SourceDirectory .\test-input `
  -OutputDirectory .\organized `
  -GroupBy dest `
  -Copy
```

Dry run:

```powershell
powershell -ExecutionPolicy Bypass -File .\organize-nfe-xml.ps1 `
  -SourceDirectory .\test-input `
  -OutputDirectory .\organized `
  -GroupBy emit `
  -DryRun
```

---

## Parameters

- `-SourceDirectory` : folder containing mixed XML files
- `-OutputDirectory` : destination root folder
- `-GroupBy emit|dest` : group by emitter CNPJ or recipient CNPJ
- `-Copy` : copy instead of move
- `-DryRun` : print the target structure without changing files
- `-Recurse` : search for XML files in subdirectories of the source folder

---

## Metadata Extraction Strategy

The script extracts:

- emitter CNPJ from `emit/CNPJ`
- recipient CNPJ or CPF from `dest/CNPJ` or `dest/CPF`
- issue date from `ide/dhEmi` or `ide/dEmi`
- access key from `infNFe/@Id` or the file name fallback

If the issue date is unavailable, the month is derived from the access key.

---

## Test Fixtures

This folder includes sample XML files under `test-input/` so you can run the script immediately and inspect the resulting structure.

---

## Notes

- The script does not validate the full NF-e schema.
- It is designed to be practical for file organization, not fiscal validation.
- When grouping by recipient (`-GroupBy dest`), both CNPJ and CPF are supported.
- If a file is missing the required CNPJ or month information, it is skipped and reported.
