#!/usr/bin/env ts-node

import * as fs from "node:fs/promises";
import * as path from "node:path";

// Requires ethers.
type Keccak256Fn = (utf8: Uint8Array) => string;

async function getKeccak256(): Promise<{ keccak256Hex: Keccak256Fn; toUtf8: (s: string) => Uint8Array }> {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const ethers = require("ethers");
    if (ethers?.keccak256 && ethers?.toUtf8Bytes) {
      // ethers v6
      return {
        keccak256Hex: (utf8) => ethers.keccak256(utf8),
        toUtf8: (s) => ethers.toUtf8Bytes(s),
      };
    }
    if (ethers?.utils?.keccak256 && ethers?.utils?.toUtf8Bytes) {
      // ethers v5
      return {
        keccak256Hex: (utf8) => ethers.utils.keccak256(utf8),
        toUtf8: (s) => ethers.utils.toUtf8Bytes(s),
      };
    }
  } catch {
    // ignore
  }
}

function isTestDirSegment(seg: string): boolean {
  return seg.toLowerCase() === "test";
}

async function walkDir(rootAbs: string): Promise<string[]> {
  const out: string[] = [];

  async function rec(dirAbs: string) {
    const entries = await fs.readdir(dirAbs, { withFileTypes: true });
    for (const e of entries) {
      const full = path.join(dirAbs, e.name);
      if (e.isDirectory()) {
        if (isTestDirSegment(e.name)) continue;
        await rec(full);
      } else if (e.isFile()) {
        if (e.name.endsWith(".sol")) out.push(full);
      }
    }
  }

  await rec(rootAbs);
  return out;
}

type ParsedError = {
  name: string;
  types: string[]; // canonical types only
  paramNames: string[]; // may be "" if unnamed
  paramsPretty: string; // e.g. "pool: IBasePool, feeds: AggregatorV3Interface[]"
  canonicalSig: string; // ErrorName(type1,type2)
  selector4: string; // 0x12345678
  notice: string; // extracted @notice or @dev
  fileBase: string; // e.g. ILPOracleBase
  pkgName: string; // e.g. interfaces
  dirRelFromContracts: string; // posix path, "" for root
};

function normalizeType(t: string): string {
  let s = t.trim();

  // Strip occasional qualifiers if present
  s = s.replace(/\b(memory|calldata|storage|payable)\b/g, "").trim();

  // Collapse whitespace
  s = s.replace(/\s+/g, " ");

  // Remove spaces around punctuation
  s = s.replace(/\s*([(),[\]])\s*/g, "$1");

  return s;
}

function splitTopLevelCommaList(s: string): string[] {
  const parts: string[] = [];
  let cur = "";
  let depthParen = 0;
  let depthBrack = 0;

  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === "(") depthParen++;
    else if (ch === ")") depthParen = Math.max(0, depthParen - 1);
    else if (ch === "[") depthBrack++;
    else if (ch === "]") depthBrack = Math.max(0, depthBrack - 1);

    if (ch === "," && depthParen === 0 && depthBrack === 0) {
      parts.push(cur.trim());
      cur = "";
    } else {
      cur += ch;
    }
  }
  if (cur.trim().length) parts.push(cur.trim());
  return parts;
}

function extractTypeFromParam(param: string): string {
  // "IBasePool pool" => "IBasePool"
  // "AggregatorV3Interface[] feeds" => "AggregatorV3Interface[]"
  // "(uint256,address) foo" => "(uint256,address)"
  const p = param.trim();
  if (!p) return "";

  const m = p.match(/^(.+?)\s+([A-Za-z_]\w*)$/);
  if (m) return normalizeType(m[1]);

  return normalizeType(p);
}

function extractNameFromParam(param: string): string {
  const p = param.trim();
  const m = p.match(/^(.+?)\s+([A-Za-z_]\w*)$/);
  return m ? m[2] : "";
}

function prettyParams(types: string[], names: string[]): string {
  if (!types.length) return "";
  const parts: string[] = [];
  for (let i = 0; i < types.length; i++) {
    const n = (names[i] ?? "").trim();
    const t = (types[i] ?? "").trim();
    parts.push(n ? `${n}: ${t}` : t);
  }
  return parts.join(", ");
}

function parseNatSpecNotice(natspecLines: string[]): string {
  function extractTag(tag: "notice" | "dev"): string | null {
    const re = new RegExp(String.raw`@${tag}\b`, "i");
    let start = -1;
    for (let i = 0; i < natspecLines.length; i++) {
      if (re.test(natspecLines[i])) {
        start = i;
        break;
      }
    }
    if (start === -1) return null;

    const first = natspecLines[start];
    const idx = first.toLowerCase().indexOf(`@${tag}`);
    let text = first.slice(idx + (`@${tag}`).length).trim();

    const cont: string[] = [];
    for (let i = start + 1; i < natspecLines.length; i++) {
      const line = natspecLines[i].trim();
      if (line.startsWith("@")) break;
      if (line.length === 0) continue;
      cont.push(line);
    }

    if (cont.length) text = (text ? text + " " : "") + cont.join(" ");
    return text || null;
  }

  const notice = extractTag("notice");
  if (notice) return notice;
  const dev = extractTag("dev");
  if (dev) return dev;
  return "";
}

function cleanNatSpecLine(line: string): string {
  let s = line.trim();
  if (s.startsWith("///")) s = s.slice(3).trim();
  if (s.startsWith("*")) s = s.slice(1).trim();
  return s;
}

function posixRel(p: string): string {
  return p.split(path.sep).join(path.posix.sep);
}

function heading(level: number, text: string): string {
  const lvl = Math.min(6, Math.max(1, level));
  return `${"#".repeat(lvl)} ${text}\n`;
}

function mdEscapeCell(s: string): string {
  return s.replace(/\|/g, "\\|").replace(/\r?\n/g, " ").trim();
}

function slugifyHeading(s: string): string {
  return s
    .trim()
    .toLowerCase()
    .replace(/[^\w\s-]/g, "")
    .replace(/\s+/g, "-");
}

function linkToErrorsMdAnchor(anchorText: string): string {
  return `errors.md#${slugifyHeading(anchorText)}`;
}

async function parseSolFile(
  fileAbs: string,
  pkgName: string,
  contractsAbs: string,
  keccak256Hex: Keccak256Fn,
  toUtf8: (s: string) => Uint8Array
): Promise<ParsedError[]> {
  const src = await fs.readFile(fileAbs, "utf8");
  const lines = src.split(/\r?\n/);

  const fileBase = path.basename(fileAbs, ".sol");
  const dirRel = path.relative(contractsAbs, path.dirname(fileAbs));
  const dirRelPosix = dirRel === "." ? "" : posixRel(dirRel);

  const errors: ParsedError[] = [];

  let i = 0;
  let pendingNatSpec: string[] = [];

  while (i < lines.length) {
    const line = lines[i];

    // Capture NatSpec blocks immediately above an item
    if (line.trim().startsWith("///")) {
      const buf: string[] = [];
      while (i < lines.length && lines[i].trim().startsWith("///")) {
        buf.push(cleanNatSpecLine(lines[i]));
        i++;
      }
      pendingNatSpec = buf;
      continue;
    }

    if (line.trim().startsWith("/**")) {
      const buf: string[] = [];
      buf.push(cleanNatSpecLine(line.replace("/**", "")));
      i++;
      while (i < lines.length && !lines[i].includes("*/")) {
        buf.push(cleanNatSpecLine(lines[i]));
        i++;
      }
      if (i < lines.length) {
        const tail = lines[i];
        const before = tail.split("*/")[0];
        if (before.trim().length) buf.push(cleanNatSpecLine(before));
        i++;
      }

      const joined = buf.join("\n");
      if (/@notice\b/i.test(joined) || /@dev\b/i.test(joined)) pendingNatSpec = buf;
      else pendingNatSpec = [];
      continue;
    }

    if (line.trim().length === 0) {
      i++;
      continue;
    }

    // Detect error declaration
    const errIdx = line.search(/\berror\b/);
    if (errIdx !== -1) {
      let decl = line.slice(errIdx);
      let j = i + 1;
      while (!decl.includes(";") && j < lines.length) {
        decl += "\n" + lines[j];
        j++;
      }

      const semi = decl.indexOf(";");
      if (semi !== -1) decl = decl.slice(0, semi + 1);
      decl = decl.trim();

      const m = decl.match(/^error\s+([A-Za-z_]\w*)\s*(\(([\s\S]*?)\))?\s*;/);
      if (m) {
        const name = m[1];
        const rawParams = (m[3] ?? "").trim();

        const types: string[] = [];
        const paramNames: string[] = [];

        if (rawParams.length) {
          const params = splitTopLevelCommaList(rawParams);
          for (const p of params) {
            const t = extractTypeFromParam(p);
            if (t) {
              types.push(t);
              paramNames.push(extractNameFromParam(p));
            }
          }
        }

        const canonicalSig = `${name}(${types.join(",")})`;
        const fullHash = keccak256Hex(toUtf8(canonicalSig));
        const selector4 = fullHash.slice(0, 10);

        const notice = parseNatSpecNotice(pendingNatSpec);
        const paramsPretty = prettyParams(types, paramNames);

        errors.push({
          name,
          types,
          paramNames,
          paramsPretty,
          canonicalSig,
          selector4,
          notice,
          fileBase,
          pkgName,
          dirRelFromContracts: dirRelPosix,
        });
      }

      i = j;
      pendingNatSpec = [];
      continue;
    }

    pendingNatSpec = [];
    i++;
  }

  return errors;
}

function sortKeyForDir(pkgName: string, dirRel: string): string {
  const d = dirRel || "";
  return `${pkgName}/${d}`;
}

async function main() {
  const repoRoot = process.cwd();
  const pkgRoot = path.join(repoRoot, "pkg");
  const errorsOutPath = path.join(repoRoot, "docs", "errors.md");
  const indexOutPath = path.join(repoRoot, "docs", "error-index.md");

  const { keccak256Hex, toUtf8 } = await getKeccak256();

  // Discover packages under /pkg
  let pkgEntries: string[] = [];
  try {
    const entries = await fs.readdir(pkgRoot, { withFileTypes: true });
    pkgEntries = entries.filter((e) => e.isDirectory()).map((e) => e.name);
  } catch {
    throw new Error(`Could not read ${pkgRoot}. Are you running from repo root?`);
  }

  pkgEntries.sort((a, b) => a.localeCompare(b));

  const allErrors: ParsedError[] = [];

  for (const pkgName of pkgEntries) {
    const contractsAbs = path.join(pkgRoot, pkgName, "contracts");
    try {
      const st = await fs.stat(contractsAbs);
      if (!st.isDirectory()) continue;
    } catch {
      continue;
    }

    const solFiles = await walkDir(contractsAbs);
    solFiles.sort((a, b) => a.localeCompare(b));

    for (const f of solFiles) {
      const parsed = await parseSolFile(f, pkgName, contractsAbs, keccak256Hex, toUtf8);
      allErrors.push(...parsed);
    }
  }

  // Group: pkg -> dir -> file -> errors
  const byPkg = new Map<string, Map<string, Map<string, ParsedError[]>>>();

  for (const e of allErrors) {
    if (!byPkg.has(e.pkgName)) byPkg.set(e.pkgName, new Map());
    const byDir = byPkg.get(e.pkgName)!;

    const dirKey = e.dirRelFromContracts; // "" for contracts root
    if (!byDir.has(dirKey)) byDir.set(dirKey, new Map());
    const byFile = byDir.get(dirKey)!;

    if (!byFile.has(e.fileBase)) byFile.set(e.fileBase, []);
    byFile.get(e.fileBase)!.push(e);
  }

  // Sort each file's errors by canonicalSig (supports overload-ish clarity)
  for (const [, byDir] of byPkg) {
    for (const [, byFile] of byDir) {
      for (const [, errs] of byFile) {
        errs.sort((a, b) => a.canonicalSig.localeCompare(b.canonicalSig));
      }
    }
  }

  // --- Build docs/errors.md ---
  let md = "";
  md += `<!-- AUTO-GENERATED. DO NOT EDIT MANUALLY. -->\n`;
  md += `<!-- Generated from /pkg/*/contracts/**/*.sol (excluding /test/). -->\n\n`;
  md += `# Errors\n\n`;

  const pkgs = Array.from(byPkg.keys()).sort((a, b) => a.localeCompare(b));
  for (const pkgName of pkgs) {
    md += heading(1, pkgName);

    const byDir = byPkg.get(pkgName)!;
    const dirKeys = Array.from(byDir.keys()).sort((a, b) => {
      if (a === "" && b !== "") return -1;
      if (b === "" && a !== "") return 1;
      const ak = sortKeyForDir(pkgName, a);
      const bk = sortKeyForDir(pkgName, b);
      return ak.localeCompare(bk);
    });

    for (const dirRel of dirKeys) {
      const byFile = byDir.get(dirRel)!;

      // Directory heading (skip for contracts root)
      let dirHeadingLevel = 1;
      if (dirRel !== "") {
        const depth = dirRel.split("/").filter(Boolean).length;
        dirHeadingLevel = 2 + (depth - 1);
        md += heading(dirHeadingLevel, `${pkgName}/${dirRel}`);
      }

      const files = Array.from(byFile.keys()).sort((a, b) => a.localeCompare(b));
      for (const fileBase of files) {
        const errs = byFile.get(fileBase)!;
        if (errs.length === 0) continue;

        const fileHeadingLevel = Math.min(6, dirRel === "" ? 2 : dirHeadingLevel + 1);
        md += heading(fileHeadingLevel, fileBase);

        md += `| Error | Arguments | Comment | Signature |\n`;
        md += `| --- | --- | --- | --- |\n`;

        for (const e of errs) {
          const errorCell = e.types.length ? e.canonicalSig : e.name;
          md += `| ${mdEscapeCell(errorCell)} | ${mdEscapeCell(e.paramsPretty)} | ${mdEscapeCell(
            e.notice || ""
          )} | \`${e.selector4}\` |\n`;
        }
        md += `\n`;
      }
    }
  }

  await fs.mkdir(path.dirname(errorsOutPath), { recursive: true });
  await fs.writeFile(errorsOutPath, md, "utf8");

  // eslint-disable-next-line no-console
  console.log(`Wrote ${path.relative(repoRoot, errorsOutPath)} with ${allErrors.length} errors.`);

  // --- Build docs/error-index.md ---
  const indexRows = [...allErrors].sort((a, b) => {
    const s = a.selector4.localeCompare(b.selector4);
    if (s !== 0) return s;
    return a.canonicalSig.localeCompare(b.canonicalSig);
  });

  let idx = "";
  idx += `<!-- AUTO-GENERATED. DO NOT EDIT MANUALLY. -->\n`;
  idx += `<!-- Generated from /pkg/*/contracts/**/*.sol (excluding /test/). -->\n\n`;
  idx += `# Error selector index\n\n`;
  idx += `Sorted by selector (4-byte).\n\n`;
  idx += `| Selector | Error | Arguments | Location |\n`;
  idx += `| --- | --- | --- | --- |\n`;

  for (const e of indexRows) {
    // Link to the file heading in errors.md
    const anchorText = e.fileBase;
    const relLocation = `${e.pkgName}${e.dirRelFromContracts ? "/" + e.dirRelFromContracts : ""}/${e.fileBase}.sol`;
    const locLink = `[${mdEscapeCell(relLocation)}](${linkToErrorsMdAnchor(anchorText)})`;

    idx += `| \`${e.selector4}\` | ${mdEscapeCell(e.canonicalSig)} | ${mdEscapeCell(e.paramsPretty)} | ${locLink} |\n`;
  }

  await fs.mkdir(path.dirname(indexOutPath), { recursive: true });
  await fs.writeFile(indexOutPath, idx, "utf8");

  // eslint-disable-next-line no-console
  console.log(`Wrote ${path.relative(repoRoot, indexOutPath)} with ${indexRows.length} entries.`);
}

main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error(err?.stack || String(err));
  process.exit(1);
});
