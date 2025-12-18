#!/usr/bin/env ts-node

import * as fs from "node:fs/promises";
import * as path from "node:path";

// Prefer ethers if present (common in solidity repos). Fall back to @noble/hashes/sha3 if you want.
type Keccak256Fn = (utf8: Uint8Array) => string;

async function getKeccak256(): Promise<{ keccak256Hex: Keccak256Fn; toUtf8: (s: string) => Uint8Array }> {
  try {
    // ethers v6
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const ethers = require("ethers");
    if (ethers?.keccak256 && ethers?.toUtf8Bytes) {
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

  // Optional fallback: @noble/hashes/sha3 (keccak_256)
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { keccak_256 } = require("@noble/hashes/sha3");
    return {
      keccak256Hex: (utf8) => {
        const digest: Uint8Array = keccak_256(utf8);
        return "0x" + Buffer.from(digest).toString("hex");
      },
      toUtf8: (s) => new TextEncoder().encode(s),
    };
  } catch {
    throw new Error(
      `Could not load keccak256 implementation. Install "ethers" or "@noble/hashes".`
    );
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
  types: string[];            // canonical types only
  canonicalSig: string;       // ErrorName(type1,type2)
  selector4: string;          // 0x12345678
  notice: string;             // extracted @notice or @dev
  fileBase: string;           // e.g. ILPOracleBase
  pkgName: string;            // e.g. interfaces
  dirRelFromContracts: string; // posix path, "" for root
};

function normalizeType(t: string): string {
  // Remove excess whitespace but preserve meaningful tokens like [] and nested tuples
  // Also normalize spaces around commas and parentheses.
  let s = t.trim();

  // Common Solidity qualifiers that should not appear in error params, but if present, strip safely.
  // (keeps this robust if someone wrote them anyway).
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
  // Goal: turn "IBasePool pool" => "IBasePool"
  //       "AggregatorV3Interface[] feeds" => "AggregatorV3Interface[]"
  //       "(uint256,address) foo" => "(uint256,address)" (tuple type)
  // If there is no clear name, keep as-is.
  const p = param.trim();
  if (!p) return "";

  // If it looks like "... <identifier>" at the end, treat that as the name and remove it.
  // This handles most "type name" forms, including complex types with spaces.
  const m = p.match(/^(.+?)\s+([A-Za-z_]\w*)$/);
  if (m) return normalizeType(m[1]);

  return normalizeType(p);
}

function parseNatSpecNotice(natspecLines: string[]): string {
  // Extract @notice (preferred) or @dev, including continuation lines until next @tag.
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
  return ""; // if missing, still emit (but empty) to make gaps obvious
}

function cleanNatSpecLine(line: string): string {
  // Strip leading /// or leading * in block comment lines
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
  // Minimal escaping for markdown tables
  return s.replace(/\|/g, "\\|").replace(/\r?\n/g, " ").trim();
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
      // consecutive /// lines
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
      // read until */
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
      // Only treat as NatSpec if it contains @notice or @dev; otherwise discard.
      const joined = buf.join("\n");
      if (/@notice\b/i.test(joined) || /@dev\b/i.test(joined)) pendingNatSpec = buf;
      else pendingNatSpec = [];
      continue;
    }

    // If blank line, keep pendingNatSpec (NatSpec often separated by blank lines in practice)
    if (line.trim().length === 0) {
      i++;
      continue;
    }

    // Try to detect an error declaration start on this line
    // We accept possible leading whitespace and optional "error" not preceded by identifier char.
    const errIdx = line.search(/\berror\b/);
    if (errIdx !== -1) {
      // accumulate until semicolon
      let decl = line.slice(errIdx);
      let j = i + 1;
      while (!decl.includes(";") && j < lines.length) {
        decl += "\n" + lines[j];
        j++;
      }

      // Chop after first semicolon
      const semi = decl.indexOf(";");
      if (semi !== -1) decl = decl.slice(0, semi + 1);

      // Remove "error" keyword prefix whitespace
      decl = decl.trim();

      // Match: error Name(...);
      const m = decl.match(/^error\s+([A-Za-z_]\w*)\s*(\(([\s\S]*?)\))?\s*;/);
      if (m) {
        const name = m[1];
        const rawParams = (m[3] ?? "").trim();

        const types: string[] = [];
        if (rawParams.length) {
          const params = splitTopLevelCommaList(rawParams);
          for (const p of params) {
            const t = extractTypeFromParam(p);
            if (t) types.push(t);
          }
        }

        const canonicalSig = `${name}(${types.join(",")})`;
        const fullHash = keccak256Hex(toUtf8(canonicalSig));
        const selector4 = fullHash.slice(0, 10); // 0x + 8 hex chars

        const notice = parseNatSpecNotice(pendingNatSpec);

        errors.push({
          name,
          types,
          canonicalSig,
          selector4,
          notice,
          fileBase,
          pkgName,
          dirRelFromContracts: dirRelPosix,
        });
      }

      // After consuming a declaration, advance i to j and clear NatSpec buffer
      i = j;
      pendingNatSpec = [];
      continue;
    }

    // Any other non-empty, non-comment line breaks the NatSpec association
    pendingNatSpec = [];
    i++;
  }

  return errors;
}

function sortKeyForDir(pkgName: string, dirRel: string): string {
  // Stable ordering: root first, then lexicographic
  const d = dirRel || "";
  return `${pkgName}/${d}`;
}

function slugifyHeading(s: string): string {
  // GitHub-style anchor slug (approx): lowercase, remove punctuation, spaces -> hyphens.
  // Good enough for typical Solidity filenames/paths.
  return s
    .trim()
    .toLowerCase()
    .replace(/[^\w\s-]/g, "")
    .replace(/\s+/g, "-");
}

function linkToErrorsMdAnchor(anchorText: string): string {
  return `errors.md#${slugifyHeading(anchorText)}`;
}

async function main() {
  const repoRoot = process.cwd();
  const pkgRoot = path.join(repoRoot, "pkg");
  const outPath = path.join(repoRoot, "docs", "errors.md");

  const { keccak256Hex, toUtf8 } = await getKeccak256();

  // Discover packages under /pkg
  let pkgEntries: string[] = [];
  try {
    const entries = await fs.readdir(pkgRoot, { withFileTypes: true });
    pkgEntries = entries.filter((e) => e.isDirectory()).map((e) => e.name);
  } catch (e) {
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

  // Sort each file's errors by canonicalSig (stable / supports overloads)
  for (const [, byDir] of byPkg) {
    for (const [, byFile] of byDir) {
      for (const [, errs] of byFile) {
        errs.sort((a, b) => a.canonicalSig.localeCompare(b.canonicalSig));
      }
    }
  }

  // Build markdown
  let md = "";
  md += `<!-- AUTO-GENERATED. DO NOT EDIT MANUALLY. -->\n`;
  md += `<!-- Generated from /pkg/*/contracts/**/*.sol (excluding /test/). -->\n\n`;
  md += `# Errors\n\n`;

  const pkgs = Array.from(byPkg.keys()).sort((a, b) => a.localeCompare(b));
  for (const pkgName of pkgs) {
    md += heading(1, pkgName);

    const byDir = byPkg.get(pkgName)!;
    const dirKeys = Array.from(byDir.keys()).sort((a, b) => {
      const ak = sortKeyForDir(pkgName, a);
      const bk = sortKeyForDir(pkgName, b);
      // Root first
      if (a === "" && b !== "") return -1;
      if (b === "" && a !== "") return 1;
      return ak.localeCompare(bk);
    });

    for (const dirRel of dirKeys) {
      const byFile = byDir.get(dirRel)!;

      // Directory heading (skip for contracts root)
      let dirHeadingLevel = 1;
      if (dirRel !== "") {
        const depth = dirRel.split("/").filter(Boolean).length; // 1 => immediate subdir
        dirHeadingLevel = 2 + (depth - 1); // depth1=>2, depth2=>3, ...
        const title = `${pkgName}/${dirRel}`;
        md += heading(dirHeadingLevel, title);
      }

      const files = Array.from(byFile.keys()).sort((a, b) => a.localeCompare(b));
      for (const fileBase of files) {
        const errs = byFile.get(fileBase)!;
        if (errs.length === 0) continue;

        const fileHeadingLevel = Math.min(6, (dirRel === "" ? 2 : dirHeadingLevel + 1));
        md += heading(fileHeadingLevel, fileBase);

        md += `| Error | Comment | Signature |\n`;
        md += `| --- | --- | --- |\n`;

        for (const e of errs) {
          const errorCell = e.types.length ? e.canonicalSig : e.name;
          const commentCell = e.notice || "";
          md += `| ${mdEscapeCell(errorCell)} | ${mdEscapeCell(commentCell)} | \`${e.selector4}\` |\n`;
        }

        md += `\n`;
      }
    }
  }

  // Ensure /docs exists
  await fs.mkdir(path.dirname(outPath), { recursive: true });
  await fs.writeFile(outPath, md, "utf8");

  // eslint-disable-next-line no-console
  console.log(`Wrote ${path.relative(repoRoot, outPath)} with ${allErrors.length} errors.`);

  // --- error-index.md ---
  const indexPath = path.join(repoRoot, "docs", "error-index.md");

  // Build index rows (one row per error), sorted by selector then canonicalSig.
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
  idx += `| Selector | Error | Location |\n`;
  idx += `| --- | --- | --- |\n`;

  for (const e of indexRows) {
    const errorCell = e.canonicalSig; // always include canonical in index
    // Link target: file heading in errors.md (stable and avoids needing per-error anchors)
    const anchorText = e.fileBase;
    const relLocation = `${e.pkgName}${e.dirRelFromContracts ? "/" + e.dirRelFromContracts : ""}/${e.fileBase}.sol`;

    const locLink = `[${mdEscapeCell(relLocation)}](${linkToErrorsMdAnchor(anchorText)})`;
    idx += `| \`${e.selector4}\` | ${mdEscapeCell(errorCell)} | ${locLink} |\n`;
  }

  await fs.mkdir(path.dirname(indexPath), { recursive: true });
  await fs.writeFile(indexPath, idx, "utf8");
  console.log(`Wrote ${path.relative(repoRoot, indexPath)} with ${indexRows.length} entries.`);
}

main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error(err?.stack || String(err));
  process.exit(1);
});

