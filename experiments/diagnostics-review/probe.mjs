import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
const binary = process.env.GOLEM_BIN;
assert.ok(path.isAbsolute(binary));
const project = fs.mkdtempSync(path.join(os.tmpdir(), "golem-review-diag-"));
const file = (p) => path.join(project, p);
const write = (p, s) => fs.writeFileSync(file(p), s);
const results = {};
function cli(args, json = true) {
	const child = spawnSync(
		binary,
		[...args, ...(json ? ["--format", "json"] : [])],
		{ cwd: project, encoding: "utf8" },
	);
	if (!json)
		return { exit: child.status, out: child.stdout, err: child.stderr };
	const parsed = JSON.parse(child.stderr.trim() || child.stdout.trim());
	return {
		exit: child.status,
		ds: (Array.isArray(parsed) ? parsed : parsed.diagnostics).map(
			({ code, severity, span, message }) => ({
				code,
				severity,
				file: span.file,
				line: span.line,
				column: span.column,
				message,
			}),
		),
	};
}
const manifest =
	fs
		.readFileSync(
			"modules/golem-driver/test/fixtures/sample/manifest.toml",
			"utf8",
		)
		.replace(/^chapters = .*/, 'chapters = ["a.gm"]') + "\n[targets.pdf]\n";
const style =
	'[page]\nsize = "A5"\nbinding = "left"\nwriting-mode = "horizontal"\n[page.grid]\nfont-size = "10pt"\ncharacters = 12\nlines = 30\nline-pitch = "15pt"\ncolumns = 1\nposition = { top = "18mm", gutter = "20mm" }\n[fonts.body]\nja = "ja.otf"\n';
const body = "本文。\n";
const ok = () => {
	write("manifest.toml", manifest);
	write("style.toml", style);
	write("a.gm", body);
};
function rules(source) {
	write("preflight.toml", source);
	return cli(["preflight"]);
}
function recover(source) {
	const lines = source.split("\n"),
		kept = [],
		removed = new Set();
	for (;;) {
		const out = rules(lines.join("\n"));
		const failures = out.ds.filter((d) =>
			["G09001", "G09104"].includes(d.code),
		);
		if (!failures.length)
			return {
				ds: [
					...kept,
					...out.ds.filter((d) => path.basename(d.file) === "preflight.toml"),
				],
				complete: true,
			};
		const d = failures[0],
			idx = d.line - 1;
		kept.push(d);
		// Only a single-line assignment with a self-contained scalar error has a known end.
		if (
			removed.has(idx) ||
			!/^\s*[\w-]+\s*=\s*[@!?]+\s*(?:#.*)?$/.test(lines[idx])
		)
			return { ds: kept, complete: false };
		removed.add(idx);
		// Preserve all UTF-8 offsets and the newline of the excluded entry.
		lines[idx] = " ".repeat(Buffer.byteLength(lines[idx]));
	}
}
try {
	ok();
	fs.copyFileSync(
		"modules/golem-font/test/fonts/SourceHanSans-Regular_subset.otf",
		file("ja.otf"),
	);
	const multi =
		'name = @\nunknown-top = 1\n[glyph-missing]\nseverity = ?\n[bleed-size]\nseverity = "invalid"\n';
	results.rulesBefore = rules(multi);
	results.rulesRecovered = recover(multi);
	results.opaque = recover(
		'name = """unfinished\n[bleed-size]\nseverity = "invalid"\n',
	);
	const both = "####### one\n\n####### two\n";
	write("a.gm", both);
	results.twoHeadings = cli(["check"]);
	for (const tag of [
		"ja-JP",
		"en-US",
		"JP",
		"US",
		"DE",
		"de",
		"jbo",
		"sl-rozaj",
		"ja-x-my-dialect",
		"ja_JP",
	]) {
		write(
			"manifest.toml",
			manifest.replace('language = "ja"', 'language = "' + tag + '"'),
		);
		write("a.gm", body);
		const r = cli(["build", "--target", "html"]);
		if (r.exit === 0) {
			const pages = fs
				.readdirSync(file("build/html"), { recursive: true })
				.filter((p) => p.endsWith(".html") || p.endsWith(".xhtml"));
			const emitted = new Set(
				pages.flatMap((p) =>
					[
						...fs
							.readFileSync(file("build/html/" + p), "utf8")
							.matchAll(/<html[^>]*? lang="([^"]+)"/g),
					].map((m) => m[1]),
				),
			);
			r.htmlLanguage = [...emitted];
		}
		results["language/" + tag] = r;
	}
	for (const profile of ["dev", "prod"]) {
		ok();
		const good = cli(["build", "--target", "pdf", "--profile", "dev"]);
		assert.equal(good.exit, 0);
		const old = fs
			.readdirSync(file("build/pdf"))
			.filter((x) => x.endsWith(".pdf"))[0];
		const priorPages = fs.readFileSync(file("build/pdf/pages.json"));
		const prior = fs.readFileSync(file("build/pdf/" + old));
		write("a.gm", '# 章\n\n@figure broken.png alt="x"\n');
		write("broken.png", Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
		const failed = cli(["build", "--target", "pdf", "--profile", profile]);
		results["stale/" + profile] = {
			codes: failed.ds.map((d) => d.code),
			exit: failed.exit,
			pdfSame:
				fs.existsSync(file("build/pdf/" + old)) &&
				fs.readFileSync(file("build/pdf/" + old)).equals(prior),
			pages: fs.existsSync(file("build/pdf/pages.json")),
			pagesSame:
				fs.existsSync(file("build/pdf/pages.json")) &&
				fs.readFileSync(file("build/pdf/pages.json")).equals(priorPages),
		};
	}
	ok();
	write("a.gm", '# 章\n\n@figure broken.png alt="x"\n');
	write("preflight.toml", 'based-on = "print"\n');
	results.missingView = cli(["preflight"]);
	ok();
	write("a.gm", "本文。\uE000\n");
	results.glyphAndBleed = cli(["preflight"]);
	if (process.env.REVISED_EXPECTATIONS) {
		assert.deepEqual(
			results.rulesRecovered.ds
				.map((d) => [d.code, d.line])
				.sort((a, b) => a[1] - b[1]),
			[
				["G09001", 1],
				["G09103", 2],
				["G09001", 4],
				["G09102", 6],
			],
		);
		assert.equal(results.opaque.complete, false);
		assert.deepEqual(
			results.twoHeadings.ds
				.filter((x) => x.code === "G01012")
				.map((x) => x.line),
			[1, 3],
		);
		assert.deepEqual(results["stale/dev"], {
			codes: ["G08010"],
			exit: 1,
			pdfSame: true,
			pages: true,
			pagesSame: true,
		});
		assert.deepEqual(results["stale/prod"], {
			codes: ["G08010"],
			exit: 1,
			pdfSame: false,
			pages: false,
			pagesSame: false,
		});
		assert.deepEqual(results.missingView.ds.map((d) => d.code).sort(), [
			"G08010",
			"G09010",
		]);
		for (const tag of [
			"ja-JP",
			"en-US",
			"JP",
			"US",
			"DE",
			"de",
			"jbo",
			"sl-rozaj",
			"ja-x-my-dialect",
		]) {
			assert.equal(results["language/" + tag].exit, 0);
			assert.deepEqual(results["language/" + tag].htmlLanguage, [tag]);
		}
		assert.equal(results["language/ja_JP"].exit, 1);
	}
	console.log(JSON.stringify(results, null, 2));
} finally {
	fs.rmSync(project, { recursive: true, force: true });
}
