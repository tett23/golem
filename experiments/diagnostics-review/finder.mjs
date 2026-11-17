import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
const root = fs.mkdtempSync(path.join(os.tmpdir(), "golem-finder-"));
const project = path.join(root, "project"),
	foreign = path.join(root, "external");
const bin = process.env.GOLEM_BIN;
const paths = [
	".",
	"chapters",
	"build",
	"build/pdf",
	"build/html",
	"unused",
	".git",
	"nested",
	"dir-entry/.DS_Store",
];
const marker = (dir) => path.join(project, dir, ".DS_Store");
const seen = (dir) => fs.existsSync(marker(dir));
const cli = (...args) =>
	spawnSync(bin, args, { cwd: project, encoding: "utf8" }).status;
try {
	fs.mkdirSync(foreign, { recursive: true });
	fs.writeFileSync(path.join(foreign, ".DS_Store"), "external");
	for (const rel of paths) {
		fs.mkdirSync(path.join(project, rel), { recursive: true });
		fs.writeFileSync(marker(rel), "finder");
	}
	fs.symlinkSync(foreign, path.join(project, "alias"), "dir");
	fs.unlinkSync(marker("nested"));
	fs.symlinkSync(path.join(foreign, ".DS_Store"), marker("nested"));
	for (const rel of ["chapters", "nested", "dir-entry", "alias", ".git"])
		fs.writeFileSync(path.join(project, rel, "a.gm"), "# Heading\n");
	fs.writeFileSync(
		path.join(project, "manifest.toml"),
		fs
			.readFileSync(
				"modules/golem-driver/test/fixtures/sample/manifest.toml",
				"utf8",
			)
			.replace(/^chapters = .*/, 'chapters = ["chapters/a.gm"]'),
	);
	const check = cli("fmt", "--check", "chapters/a.gm");
	const afterCheck = paths.filter(seen);
	const args = [
		"chapters/a.gm",
		"alias/a.gm",
		"nested/a.gm",
		"dir-entry/a.gm",
		".git/a.gm",
	];
	const fmt = cli("fmt", ...args);
	const afterFmt = paths.filter(seen);
	const again = cli("fmt", ...args);
	fs.writeFileSync(marker("."), "finder");
	fs.writeFileSync(path.join(project, "chapters/a.gm"), "####### broken\n");
	const build = cli(
		"build",
		"--target",
		"pdf",
		"--profile",
		"dev",
		"--format",
		"json",
	);
	const afterBuild = paths.filter(seen);
	const protectedPaths = {
		foreign: fs.readFileSync(path.join(foreign, ".DS_Store"), "utf8"),
		fileLink: fs.lstatSync(marker("nested")).isSymbolicLink(),
		directory: fs.lstatSync(marker("dir-entry")).isDirectory(),
		git: seen(".git"),
		unused: seen("unused"),
		unselectedHtml: seen("build/html"),
	};
	if (process.env.REVISED_EXPECTATIONS) {
		assert.equal(check, 0);
		assert.deepEqual(afterCheck, paths);
		assert.equal(fmt, 0);
		assert.equal(again, 0);
		assert.deepEqual(
			afterFmt,
			paths.filter((p) => ![".", "chapters"].includes(p)),
		);
		assert.equal(build, 1);
		assert.deepEqual(
			afterBuild,
			paths.filter((p) => ![".", "chapters", "build", "build/pdf"].includes(p)),
		);
		assert.deepEqual(protectedPaths, {
			foreign: "external",
			fileLink: true,
			directory: true,
			git: true,
			unused: true,
			unselectedHtml: true,
		});
	}
	console.log(
		JSON.stringify(
			{
				check,
				afterCheck,
				fmt,
				afterFmt,
				again,
				build,
				afterBuild,
				protectedPaths,
			},
			null,
			2,
		),
	);
} finally {
	fs.rmSync(root, { recursive: true, force: true });
}
