package main

import (
	"flag"
	"io/ioutil"
	"log"
	"path"
	"path/filepath"

	"github.com/stephen-soltesz/epoxy-images/go/shext"
	pipe "gopkg.in/stephen-soltesz/pipe.v3"
)

var (
	vmlinuz       = flag.String("vmlinuz", "", "URL to vmlinuz image.")
	initram       = flag.String("initram", "", "URL to initram image.")
	resources     = flag.String("resources", "", "Directory with files to add to custom image.")
	customInitram = flag.String("custom", "", "Name of customized image")
)

func init() {
	// Default logging flags use `log.LstdFlags`. This disables all log
	// prefixes to emulate bash `set -x`.
	log.SetFlags(0)
}

func buildCustomImage(vmlinuzURL, initramURL, resources, customName string) error {
	outdir := path.Dir(customName)
	// Convert to an absolute path in the output directory.
	origVmlinuz := path.Join(outdir, path.Base(vmlinuzURL))
	origInitram := path.Join(outdir, path.Base(initramURL))
	builddir, err := ioutil.TempDir("", "initram-contents")
	if err != nil {
		return err
	}
	return pipe.Run(
		pipe.Script(
			"BuildCustomImage",
			shext.Download(origVmlinuz, vmlinuzURL),
			shext.Download(origInitram, initramURL),
			shext.UnpackInitram(origInitram, builddir),
			shext.RebuildSquashFS(builddir+"/usr.squashfs", resources, "share/oem"),
			shext.PackInitram(builddir, customName),
			pipe.Exec("rm", "-rf", builddir),
		),
	)
}

func absPath(relPath string) string {
	filepath, err := filepath.Abs(relPath)
	if err != nil {
		log.Fatal(err)
	}
	return filepath
}

func main() {
	flag.Parse()
	err := buildCustomImage(*vmlinuz, *initram, absPath(*resources), absPath(*customInitram))
	if err != nil {
		log.Fatalf("Error: %v", err)
	}
	log.Println("Success")
}
