import {
	mkdtempSync,
	cpSync,
	writeFileSync,
	readFileSync,
	readdirSync,
	mkdirSync,
	rmSync,
	existsSync,
	symlinkSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
const bin = process.env.GOLEM_BIN;
assert.ok(bin && path.isAbsolute(bin), "absolute GOLEM_BIN required");
const root = mkdtempSync(path.join(tmpdir(), "golem-diagnostic-probe-"));
const write = (file, s) => writeFileSync(path.join(root, file), s);
const fixture = "modules/golem-driver/test/fixtures/sample";
const manifest =
	readFileSync(fixture + "/manifest.toml", "utf8").replace(
		/^chapters = .*/,
		'chapters = ["a.gm"]',
	) + "\n[targets.pdf]\n";
const codes = (r) => r.d.map((x) => x.code);
function run(...args) {
	const p = spawnSync(bin, [...args, "--format", "json"], {
		cwd: root,
		encoding: "utf8",
		env: { ...process.env, XDG_CACHE_HOME: root + "/cache" },
	});
	let parsed;
	for (const output of [p.stderr, p.stdout]) {
		try {
			parsed = JSON.parse(output);
			break;
		} catch {}
	}
	assert.ok(parsed, p.stderr + " " + p.stdout);
	return {
		exit: p.status,
		d: Array.isArray(parsed) ? parsed : parsed.diagnostics,
	};
}
const results = {};
try {
	write("manifest.toml", manifest);
	write("a.gm", "本文。\n");
	cpSync(
		"modules/golem-font/test/fonts/SourceHanSans-Regular_subset.otf",
		root + "/ja.otf",
	);
	write(
		"style.toml",
		'[page]\nsize = "A5"\nbinding = "left"\nwriting-mode = "horizontal"\n[page.grid]\nfont-size = "10pt"\ncharacters = 12\nlines = 30\nline-pitch = "15pt"\ncolumns = 1\nposition = { top = "18mm", gutter = "20mm" }\n[fonts.body]\nja = "ja.otf"\n',
	);
	for (const [label, s] of Object.entries({
		absent: null,
		utf8: Buffer.from([255]),
		syntax: "[",
		duplicate: 'name = "a"\nname = "b"',
		unknown: "what = 1",
		mixed: 'what = 1\n[glyph-missing]\nseverity = "no"',
		value: '[glyph-missing]\nseverity = "no"',
	})) {
		if (s !== null) write("rules.toml", s);
		const r = run("preflight", "--rules", "rules.toml");
		results["rules-" + label] = r;
		assert.equal(r.exit, 1);
	}
	for (const [label, chapters] of Object.entries({
		one: '["a.gm"]',
		nested: '[["a.gm"]]',
		repeat: '["a.gm", "a.gm"]',
		two: '["a.gm", "b.gm"]',
	})) {
		write("a.gm", "####### X\n\n####### Y\n");
		write("b.gm", "####### X\n");
		write("manifest.toml", manifest.replace('["a.gm"]', chapters));
		const data = [run("check"), run("build", "--target", "html")].map((r) =>
			r.d.filter((x) => x.code === "G01012").map((x) => x.span),
		);
		results["heading-" + label] = data;
	}
	for (const [label, chapters] of Object.entries({
		shared: '["a.gm", "b.gm"]',
		chapterImport: '["a.gm", "shared.gm"]',
	})) {
		write("manifest.toml", manifest.replace('["a.gm"]', chapters));
		for (const file of ["a.gm", "b.gm"])
			write(file, "@import shared.gm as common\n\n本文。\n");
		write("shared.gm", "####### X\n");
		results["heading-" + label] = [
			run("check"),
			run("build", "--target", "html"),
		].map((r) => r.d.filter((x) => x.code === "G01012").map((x) => x.span));
	}
	write("a.gm", "本文。\n");
	for (const tag of [
		"ja",
		"ja-JP",
		"ja_JP",
		"x",
		"i-klingon",
		"sl-rozaj-rozaj",
		"en-a-foo-a-bar",
	]) {
		write(
			"manifest.toml",
			manifest.replace('language = "ja"', 'language = "' + tag + '"'),
		);
		results["language-" + tag] = codes(run("build", "--target", "html"));
	}
	write(
		"manifest.toml",
		manifest.replace('language = "ja"', 'language = "ja_JP"\nbogus = 2'),
	);
	results["language-bad-schema"] = run("build", "--target", "html");
	results.languageMatrix = [];
	for (const setting of [
		"html",
		"text",
		"epub",
		"pdf",
		"pdfa",
		"pdfua",
		"check",
	]) {
		const target = setting.startsWith("pdf") ? "pdf" : setting;
		const declaration =
			setting === "pdfa"
				? 'pdfa = "2a"\n'
				: setting === "pdfua"
					? 'pdfua = "1"\n'
					: "";
		write(
			"manifest.toml",
			manifest.replace('language = "ja"', 'language = "ja_JP"') + declaration,
		);
		for (const profile of ["dev", "prod"]) {
			const args =
				setting === "check" ? ["check"] : ["build", "--target", target];
			const r = run(...args, "--profile", profile);
			results.languageMatrix.push({
				setting,
				profile,
				exit: r.exit,
				spans: r.d.filter((x) => x.code === "G03119").map((x) => x.span),
			});
		}
	}

	write("manifest.toml", manifest);
	write("a.gm", "本文。\uE000\n");
	for (const severity of ["off", "warning", "error"]) {
		write("preflight.toml", '[glyph-missing]\nseverity = "' + severity + '"\n');
		results["glyph-" + severity] = run("preflight");
	}
	for (const severity of ["off", "warning", "error"]) {
		write(
			"preflight.toml",
			'based-on = "none"\n[glyph-missing]\nseverity = "' + severity + '"\n',
		);
		results["isolated-glyph-" + severity] = run("preflight");
	}
	write("a.gm", "本文。\n");
	for (const based of ["print", "basic", "none", "screen"]) {
		write("preflight.toml", 'based-on = "' + based + '"\n');
		results["press-" + based] = codes(run("preflight"));
	}
	write(
		"preflight.toml",
		'based-on = "screen"\n[bleed-size]\nseverity = "error"\nmin = "3mm"\n',
	);
	results["screen-override"] = run("preflight");
	write("preflight.toml", 'based-on = "screen"\n');
	results["marks"] = codes(run("preflight", "--marks", "japanese"));
	cpSync("modules/golem-pdf/test/fixtures/tiny.jpg", root + "/tiny.jpg");
	write("a.gm", '# 章\n\n@figure tiny.jpg alt="t"\n');
	write("preflight.toml", 'based-on = "print"\n');
	const observed = run("preflight").d.find((x) => x.code === "G09006");
	assert.ok(observed, "fixture must emit G09006 under print");
	const ppi = observed.facts.ppi;
	for (const threshold of [ppi - 1, ppi, ppi + 1]) {
		const v =
			"{ error-below = " + threshold + ", warning-below = " + threshold + " }";
		write(
			"preflight.toml",
			'based-on = "none"\n[image-resolution]\ncolor = ' +
				v +
				"\ngray = " +
				v +
				"\nbitmap = " +
				v +
				"\n",
		);
		results["resolution-" + threshold] = Array.from({ length: 3 }, () =>
			run("preflight").d.filter((x) => x.code === "G09006"),
		);
	}
	results.ppi = ppi;
	write("a.gm", "本文。\n");
	for (const lang of ["ja", "en"]) {
		const dest = path.join(root, "template-" + lang);
		const child = spawnSync(
			bin,
			["new", dest, "--language", lang, "--no-fonts", "--screen"],
			{ encoding: "utf8" },
		);
		results["template-" + lang] = {
			exit: child.status,
			bleed:
				child.status === 0 &&
				/^bleed =/m.test(readFileSync(dest + "/style.toml", "utf8")),
			rules:
				child.status === 0
					? readFileSync(dest + "/preflight.toml", "utf8").trim()
					: null,
		};
	}
	for (const fmt of ["csv", "tsv"]) {
		const sep = fmt === "csv" ? "," : "\t";
		write("a.gm", "# 章\n\n@table data." + fmt + "\n");
		for (const [kind, content] of Object.entries({
			empty: "",
			uneven: "a" + sep + "b\nx\n",
			valid: "a" + sep + "b\nx" + sep + "y\n",
		})) {
			write("data." + fmt, content);
			results["table-" + fmt + "-" + kind] = run("build", "--target", "html");
		}
	}
	write("a.gm", "本文。\n");
	const wasm = readFileSync("plugins/wasm/auto-tcy.wasm");
	const hash = createHash("sha256").update(wasm).digest("hex");
	mkdirSync(root + "/cache/golem/plugins", { recursive: true });
	write("cache/golem/plugins/" + hash + ".wasm", wasm);
	write(
		"plugins.lock",
		'[plugins.tcy]\nurl = "https://example.com/tcy.wasm"\nsha256 = "' +
			hash +
			'"\n',
	);
	for (const [label, plugin, filter] of [
		["missing", "ghost", "x"],
		["unknown", "tcy", "missing"],
	]) {
		write(
			"manifest.toml",
			manifest +
				'\n[plugins.tcy]\nurl = "https://example.com/tcy.wasm"\n[[filters]]\nplugin = "' +
				plugin +
				'"\nfilter = "' +
				filter +
				'"\nfiles = ["a.gm"]\n',
		);
		results["filter-" + label] = run("build", "--target", "html");
	}
	write("manifest.toml", manifest);
	const chart = readFileSync(
		"modules/golem-driver/test/fixtures/figures/images/chart.pdf",
	);
	const trailer = Buffer.from("trailer\n<<");
	const offset = chart.indexOf(trailer);
	assert.ok(offset >= 0);
	cpSync(
		"modules/golem-driver/test/fixtures/figures/images/gray.png",
		root + "/fallback.png",
	);
	for (const [kind, bytes, page] of [
		[
			"encrypted",
			Buffer.concat([
				chart.subarray(0, offset + trailer.length),
				Buffer.from(" /Encrypt 1 0 R"),
				chart.subarray(offset + trailer.length),
			]),
			1,
		],
		["page", chart, 100],
	]) {
		write("chart.pdf", bytes);
		write(
			"a.gm",
			"# 章\n\n@figure chart.pdf web=fallback.png page=" + page + ' alt="t"\n',
		);
		results["pdf-" + kind] = run("build", "--target", "pdf");
	}
	write("a.gm", "本文。\n");
	const good = run("build", "--target", "pdf");
	assert.equal(good.exit, 0, JSON.stringify(good));
	write("bad.png", Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
	write("a.gm", '# 章\n\n@figure bad.png alt="t"\n');
	const bad = run("build", "--target", "pdf");
	assert.ok(codes(bad).includes("G08010"), JSON.stringify(bad));
	results.stale = {
		exit: bad.exit,
		codes: codes(bad),
		remaining: existsSync(root + "/build/pdf")
			? readdirSync(root + "/build/pdf")
			: [],
	};
	const sentinel = () => {
		mkdirSync(root + "/build/pdf", { recursive: true });
		write("build/pdf/prior.pdf", "prior");
	};
	const exists = () => existsSync(root + "/build/pdf/prior.pdf");
	for (const [label, args, m] of [
		["default-pdf", ["build"], manifest],
		["check", ["check"], manifest],
		["html", ["build", "--target", "html"], manifest],
		["default-html", ["build"], manifest.replace("[targets.pdf]", "")],
		["invalid-explicit", ["build", "--target", "pdf"], "["],
		["invalid-default", ["build"], "["],
	]) {
		sentinel();
		write("manifest.toml", m);
		write("a.gm", "####### x\n");
		const r = run(...args);
		results["cleanup-" + label] = { exit: r.exit, remaining: exists() };
	}
	rmSync(root + "/build/pdf", { recursive: true, force: true });
	mkdirSync(root + "/external");
	write("external/prior.pdf", "outside");
	symlinkSync(root + "/external", root + "/build/pdf", "dir");
	write("manifest.toml", manifest);
	write("a.gm", "本文。\n");
	const unsafe = run("build", "--target", "pdf");
	results["cleanup-link"] = {
		codes: codes(unsafe),
		remaining: readFileSync(root + "/external/prior.pdf", "utf8"),
	};
	rmSync(root + "/build/pdf");
	write("build/pdf", "file");
	const ordinary = run("build", "--target", "pdf");
	results["output-file"] = {
		codes: codes(ordinary),
		remaining: readFileSync(root + "/build/pdf", "utf8"),
	};
	rmSync(root + "/build/pdf");
	sentinel();
	rmSync(root + "/build/html", { recursive: true, force: true });
	symlinkSync(root + "/external", root + "/build/html", "dir");
	write("manifest.toml", "[");
	const sibling = run("build");
	results["cleanup-sibling"] = {
		codes: codes(sibling),
		remaining: exists(),
		external: readFileSync(root + "/external/prior.pdf", "utf8"),
	};
	console.log(JSON.stringify(results, null, 2));
} finally {
	rmSync(root, { recursive: true, force: true });
}
