// Package shext customize a coreos initram image.
package shext

import (
	"path/filepath"

	pipe "gopkg.in/stephen-soltesz/pipe.v3"
)

// Download takes a url and writes it to CWD.
func Download(file, url string) pipe.Pipe {
	return pipe.Script(
		"Download",
		pipe.Exec("curl", "--fail", "-o", file, url),
	)
}

// UnpackInitram accepts a compressed cpio archive, and unpacks the
// contents into the contents directory.
func UnpackInitram(file, contents string) pipe.Pipe {
	return pipe.Script(
		"UnpackInitram",
		pipe.MkDirAll(contents, 0777),
		pipe.Line(
			pipe.ChDir(contents),
			pipe.ReadFile(file),
			pipe.Exec("gzip", "-d", "--to-stdout"),
			pipe.Exec("cpio", "-i"),
		),
	)
}

// PackInitram creates a compressed cpio archive from the
// contents directory and writes the result to output.
func PackInitram(contents, output string) pipe.Pipe {
	return pipe.Script(
		"PackInitram",
		pipe.Line(
			pipe.ChDir(contents),
			pipe.Exec("find", "."),
			pipe.Exec("cpio", "-o", "-H", "newc"),
			pipe.Exec("gzip"),
			pipe.WriteFile(output, 0777),
		),
	)
}

// RebuildSquashFS takes the thing.
func RebuildSquashFS(squashfs, fromDir, toDir string) pipe.Pipe {
	// Extract the squashfs into a default dir name 'squashfs-root'
	// Note: xattrs do not work within a docker image, they are not necessary.
	files, err := filepath.Glob(fromDir + "/*")
	if err != nil {
		return pipe.Script(
			"RebuildSquashFS",
			pipe.System("echo Failed to find files in "+fromDir+" && false"),
		)
	}
	files = append(files, "squashfs-root/"+toDir)
	return pipe.Script(
		"RebuildSquashFS",
		pipe.Exec("unsquashfs", "-no-xattrs", squashfs),
		// NOTE: pipe.MkDirAll runs asynchronously before unsquashfs, so use mkdir instead.
		pipe.Exec("mkdir", "-p", "squashfs-root/"+toDir),
		pipe.Exec("cp", append([]string{"-r"}, files...)...),
		pipe.Exec("mksquashfs", "squashfs-root", squashfs, "-noappend", "-always-use-fragments"),
		// Cleanup
		pipe.Exec("rm", "-rf", "squashfs-root"),
	)
}
