import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
const r = JSON.parse(readFileSync(process.argv[2]));
const checks = [
	[
		"L2/target and profile",
		() => {
			const spans = r.languageMatrix.map((row) => {
				assert.equal(row.exit, 1);
				assert.equal(row.spans.length, 1);
				return row.spans[0];
			});
			assert.equal(spans.length, 14);
			assert.equal(new Set(spans.map((x) => JSON.stringify(x))).size, 1);
			assert.equal(spans[0].file, "manifest.toml");
		},
	],
	[
		"P3/other error",
		() => {
			assert.equal(r["glyph-off"].exit, 1);
			assert.ok(
				r["glyph-off"].d.some(
					(x) => x.code === "G09010" && x.severity === "error",
				),
			);
		},
	],
	[
		"D1/G09001 missing",
		() =>
			assert.deepEqual(
				r["rules-absent"].d.map((x) => x.code),
				["G09100"],
			),
	],
	[
		"D2/G09001 encoding",
		() =>
			assert.deepEqual(
				r["rules-utf8"].d.map((x) => x.code),
				["G09101"],
			),
	],
	[
		"D3/G09001 syntax",
		() =>
			assert.deepEqual(
				r["rules-syntax"].d.map((x) => x.code),
				["G09001"],
			),
	],
	[
		"D4/G09001 schema",
		() =>
			assert.deepEqual(
				r["rules-value"].d.map((x) => x.code),
				["G09102"],
			),
	],
	[
		"D5/G09001 unknown key",
		() =>
			assert.deepEqual(
				r["rules-unknown"].d.map((x) => x.code),
				["G09103"],
			),
	],
	[
		"D6/G09001 TOML duplicate",
		() =>
			assert.deepEqual(
				r["rules-duplicate"].d.map((x) => x.code),
				["G09104"],
			),
	],
	[
		"D7/mixed schema",
		() =>
			assert.deepEqual(
				r["rules-mixed"].d.map((x) => [x.code, x.span.line]),
				[
					["G09102", 3],
					["G09103", 1],
				],
			),
	],
	[
		"S3/explicit override",
		() =>
			assert.ok(
				r["screen-override"].d.some(
					(x) => x.code === "G09010" && x.severity === "error",
				),
			),
	],
	[
		"A1/resolution",
		() => {
			for (const n of [r.ppi - 1, r.ppi, r.ppi + 1]) {
				const rows = r["resolution-" + n];
				assert.ok(rows.every((row) => row.length === Number(n > r.ppi)));
				assert.equal(new Set(rows.map((x) => JSON.stringify(x))).size, 1);
			}
		},
	],
	[
		"H1/headings",
		() => {
			for (const k of [
				"one",
				"nested",
				"repeat",
				"two",
				"shared",
				"chapterImport",
			]) {
				const [a, b] = r["heading-" + k];
				assert.deepEqual(a, b);
				assert.equal(
					a.length,
					{ one: 2, nested: 2, repeat: 2, two: 3, shared: 1, chapterImport: 1 }[
						k
					],
				);
				assert.equal(new Set(a.map((x) => JSON.stringify(x))).size, a.length);
			}
		},
	],
	[
		"L1/manifest",
		() => {
			for (const tag of ["ja_JP", "x"])
				assert.ok(r["language-" + tag].includes("G03119"));
			for (const tag of ["ja", "ja-JP", "i-klingon"])
				assert.deepEqual(r["language-" + tag], []);
		},
	],
	[
		"P1/glyphs",
		() => {
			for (const s of ["off", "warning", "error"]) {
				const ds = r["glyph-" + s].d;
				assert.ok(!ds.some((x) => x.code === "G08100"));
				assert.equal(
					ds.find((x) => x.code === "G09002")?.severity,
					s === "off" ? undefined : s,
				);
				assert.ok(ds.some((x) => x.code === "G09010"));
			}
		},
	],
	[
		"P2/glyph exit",
		() => {
			for (const s of ["off", "warning", "error"])
				assert.equal(r["isolated-glyph-" + s].exit, Number(s === "error"));
		},
	],
	["B1/stale PDF", () => assert.deepEqual(r.stale.remaining, [])],
	[
		"B2/target boundary",
		() => {
			for (const key of [
				"default-pdf",
				"default-html",
				"invalid-explicit",
				"invalid-default",
			])
				assert.deepEqual(r["cleanup-" + key], { exit: 1, remaining: false });
			for (const key of ["check", "html"])
				assert.deepEqual(r["cleanup-" + key], { exit: 1, remaining: true });
		},
	],
	[
		"B3/output link",
		() => {
			assert.ok(r["cleanup-link"].codes.includes("G08013"));
			assert.equal(r["cleanup-link"].remaining, "outside");
		},
	],
	[
		"F1/plugin filter",
		() => {
			assert.deepEqual(
				r["filter-missing"].d.map((x) => x.code),
				["G06010"],
			);
			assert.deepEqual(
				r["filter-unknown"].d.map((x) => x.code),
				["G06107"],
			);
		},
	],
	[
		"L1/schema error",
		() =>
			assert.deepEqual(
				r["language-bad-schema"].d.map((x) => x.code),
				["G03001"],
			),
	],
	[
		"B4/sibling link",
		() =>
			assert.deepEqual(r["cleanup-sibling"], {
				codes: ["G03001"],
				remaining: false,
				external: "outside",
			}),
	],
	[
		"I1/import PDF",
		() => {
			for (const [kind, code] of [
				["encrypted", "G08105"],
				["page", "G08106"],
			]) {
				const ds = r["pdf-" + kind].d.filter((x) => x.severity === "error");
				assert.deepEqual(
					ds.map((x) => x.code),
					[code],
				);
				assert.equal(ds[0].span.file, "a.gm");
				assert.equal(ds[0].span.line, 3);
			}
		},
	],
	[
		"O1/output file",
		() => {
			assert.deepEqual(r["output-file"], {
				codes: ["G08104"],
				remaining: "file",
			});
			assert.ok(r["cleanup-link"].codes.includes("G08013"));
		},
	],
	[
		"T1/table cause",
		() => {
			for (const fmt of ["csv", "tsv"])
				for (const [kind, code, line] of [
					["empty", "G02085", 1],
					["uneven", "G02154", 2],
					["valid", null, null],
				]) {
					const ds = r["table-" + fmt + "-" + kind].d.filter(
						(x) => x.severity === "error",
					);
					assert.deepEqual(
						ds.map((x) => x.code),
						code ? [code] : [],
					);
					if (code) {
						assert.equal(ds[0].span.file, "data." + fmt);
						assert.equal(ds[0].span.line, line);
					}
				}
		},
	],
	[
		"S2/screen template",
		() => {
			for (const lang of ["ja", "en"]) {
				const t = r["template-" + lang];
				assert.equal(t.exit, 0);
				assert.equal(t.bleed, false);
				assert.equal(t.rules, 'based-on = "screen"');
			}
		},
	],
	[
		"S1/screen print rules",
		() => {
			assert.ok(!r["press-screen"].includes("G09001"));
			assert.ok(!r["press-screen"].includes("G09014"));
			assert.ok(!r["press-screen"].includes("G09010"));
			assert.ok(r["press-print"].includes("G09010"));
			assert.ok(r.marks.includes("G07002"));
		},
	],
];
let failed = 0;
for (const [name, check] of checks) {
	try {
		check();
		console.log("PASS " + name);
	} catch (e) {
		failed++;
		console.log("FAIL " + name + ": " + e.message);
	}
}
console.log(checks.length + " checks, " + failed + " failures");
process.exitCode = Number(failed > 0);
