import { readFileSync } from "node:fs";

/** The CSV `eval --features` writes: a header line, comma-separated fields, nothing quoted. */
export function parseCsv(text) {
  const lines = text.split("\n").filter((line) => line.length > 0);
  if (!lines.length) throw new Error("the CSV is empty");
  const columns = lines[0].split(",");
  const rows = lines.slice(1).map((line, index) => {
    const fields = line.split(",");
    if (fields.length !== columns.length) {
      throw new Error(
        `row ${index + 1} has ${fields.length} fields, the header has ${columns.length}`,
      );
    }
    return Object.fromEntries(columns.map((name, i) => [name, fields[i]]));
  });
  return { columns, rows };
}

/** Every row from every file, in order. Session names have to be distinct across files. */
export function readRows(paths) {
  const rows = [];
  for (const path of paths) {
    rows.push(...parseCsv(readFileSync(path, "utf8")).rows);
  }
  return rows;
}
