import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
const base = "0a8d21a091d830573fb6229111ed744f74162afd";
const git = (...args) =>
	execFileSync("git", args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
const catalog = git("show", base + ":docs/diagnostics.md").split("\n");
const sections = [...catalog.entries()].filter(([, s]) =>
	/^## [EG][0-9]{5}$/.test(s),
);
const files = git("ls-tree", "-r", "--name-only", base, "modules")
	.trim()
	.split("\n")
	.filter(
		(p) => /\/src(?:-[^/]+)?\/.*\.hs$/.test(p) && !p.endsWith("/Embedded.hs"),
	);
const sites = new Map(),
	floats = [],
	approximate = [];
for (const file of files) {
	const lines = git("show", base + ":" + file).split("\n");
	for (const [n, line] of lines.entries()) {
		for (const [, code] of line.matchAll(/"([EG][0-9]{5})"/g)) {
			const list = sites.get(code) ?? [];
			list.push(file + ":" + (n + 1));
			sites.set(code, list);
		}
		if (
			/\b(Double|Float|CFloat|CDouble|THalf|TFloat|TDouble|isNaN|isInfinite|logBase)\b/.test(
				line,
			)
		)
			floats.push([file, n + 1, line.trim()].join("\t"));
		if (
			/\b(floor|ceiling|round|roundTo|round17|sqrtR|sqrtRational|isqrt)\b/.test(
				line,
			)
		)
			approximate.push([file, n + 1, line.trim()].join("\t"));
	}
}
const rows = sections.map(([start, head], i) => {
	const body = catalog.slice(start + 1, sections[i + 1]?.[0] ?? catalog.length);
	const code = head.slice(3),
		title = body.find((s) => s.trim()),
		status = body.find((s) => s.startsWith("- 状態:"));
	const rationale = body
		.slice(body.indexOf("### 意味") + 1, body.indexOf("### 主な原因"))
		.join("\n");
	const candidate =
		status?.includes("使用中") &&
		/どれも|のどれか|場合にも|ときにも|にもこのコード|もこのコード|次のとおり|の理由/.test(
			rationale,
		);
	return [
		code,
		start + 1,
		status?.slice(6),
		title,
		candidate ? "候補" : "未判定",
		(sites.get(code) ?? []).join("|"),
	].join("\t");
});
writeFileSync(
	"experiments/diagnostics/catalog.tsv",
	["code\tline\tstatus\ttitle\ttriage\tliteral sites", ...rows].join("\n") +
		"\n",
);
writeFileSync("experiments/diagnostics/floating.tsv", floats.join("\n") + "\n");
writeFileSync(
	"experiments/diagnostics/rounding.tsv",
	approximate.join("\n") + "\n",
);
console.log({
	sections: sections.length,
	files: files.length,
	flagged: rows.filter((r) => r.includes("\t候補\t")).length,
	floating: floats.length,
	rounding: approximate.length,
});
