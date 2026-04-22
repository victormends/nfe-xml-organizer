# nfe-xml-organizer

A small PowerShell utility to organize NF-e XML files from a mixed folder into:

```text
<CNPJ>/<YYYY-MM>/
```

The script reads each XML, extracts the emitter or recipient CNPJ, determines the issue month, and then moves or copies the file into the correct folder structure.

This is useful when a single export folder contains XML files for multiple companies and multiple months.

## Why This Exists

This script came from a simple operational problem.

In a real workflow, XML files from different companies and different issue months had been accumulating in the same folder over time. Before those files could be handed off for accounting work, someone had to separate them by CNPJ and month.

That sorting was being done manually, which created an avoidable risk: placing XML files under the wrong company or the wrong period. For fiscal documents, that kind of mistake is easy to make and annoying to verify afterward.

This utility was built to make that step deterministic. Instead of relying on manual sorting, the script reads the metadata from each XML and places the file in the expected folder structure with the same rule every time.

---

## Assumptions

- files are NF-e XML documents
- file names follow the common pattern:

```text
<44-digit-access-key>-nfe.xml
```

- the script first tries to read metadata from the XML itself
- if the issue month is missing from the XML, it falls back to the access key in the file name

---

## Folder Structure Produced

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
