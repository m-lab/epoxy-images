package shext

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path"
	"strings"
	"testing"

	"github.com/kylelemons/godebug/pretty"
	pipe "gopkg.in/stephen-soltesz/pipe.v3"
)

func TestDownload(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/success",
		func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		},
	)
	mux.Handle("/error", http.NotFoundHandler())
	ts := httptest.NewServer(mux)
	defer ts.Close()

	type args struct {
		file string
		url  string
	}
	tests := []struct {
		name    string
		args    args
		wantErr bool
	}{
		{
			name: "error",
			args: args{
				file: "index.html",
				url:  ts.URL + "/error",
			},
			wantErr: true,
		},
		{
			name: "success",
			args: args{
				file: "index.html",
				url:  ts.URL + "/success",
			},
			wantErr: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := pipe.Run(Download(tt.args.file, tt.args.url)); (err != nil) != tt.wantErr {
				t.Errorf("Download(%s) error = %v, wantErr %v", tt.args.url, err, tt.wantErr)
			}
			// Clean up.
			if err := os.Remove(tt.args.file); !tt.wantErr && err != nil {
				t.Errorf("Download(%s) error = %v, failed to remove %s", tt.args.url, err, tt.args.file)
			}
		})
	}
}

func TestUnpackInitram(t *testing.T) {
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf("UnpackInitram() error = %v, failed to get $PWD", err)
	}
	type args struct {
		file     string
		contents string
		find     string
	}
	tests := []struct {
		name    string
		args    args
		wantErr bool
	}{
		// TODO: make this a single-case test or add a failing case.
		{
			name: "working",
			args: args{
				file:     path.Join(cwd, "testdata/unpack.cpio.gz"),
				contents: path.Join(cwd, "testdata/unpack"),
				find:     path.Join(cwd, "testdata/unpack/file.txt"),
			},
			wantErr: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := pipe.Run(UnpackInitram(tt.args.file, tt.args.contents)); (err != nil) != tt.wantErr {
				t.Errorf("UnpackInitram() error = %v, wantErr %v", err, tt.wantErr)
			}
			if _, err := os.Stat(tt.args.find); os.IsNotExist(err) {
				t.Errorf("UnpackInitram() error = %v, want %v", err, tt.args.find)
			}
			if err := os.RemoveAll(tt.args.contents); err != nil {
				t.Fatalf("UnpackInitram() error = %v, failed to clean up %s", err, tt.args.contents)
			}
		})
	}
}

func TestPackInitram(t *testing.T) {
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf("PackInitram() error = %v, failed to get $PWD", err)
	}
	type args struct {
		contents string
		output   string
	}
	tests := []struct {
		name    string
		args    args
		wantErr bool
	}{
		// TODO: make this a single-case test or add a failing case.
		{
			name: "working",
			args: args{
				contents: path.Join(cwd, "testdata/repack"),
				output:   path.Join(cwd, "testdata/repack.cpio.gz"),
			},
			wantErr: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := pipe.Run(PackInitram(tt.args.contents, tt.args.output)); (err != nil) != tt.wantErr {
				t.Errorf("PackInitram() error = %v, wantErr %v", err, tt.wantErr)
			}
			if err := os.Remove(tt.args.output); err != nil {
				t.Errorf("PackInitram() error = %v, failed to remove %s", err, tt.args.output)
			}
		})
	}
}

func listSquashfs(file string) []string {
	origB, err := pipe.Output(pipe.Exec("unsquashfs", "-l", file))
	if err != nil {
		fmt.Printf("listSquashfs() error = %v, could not list contents of %s", err, file)
		return nil
	}
	origFields := strings.Split(string(origB), "\n")
	return origFields[3 : len(origFields)-1]
}

func TestRebuildSquashFS(t *testing.T) {
	type args struct {
		squashfs string
		fromDir  string
		toDir    string
	}
	tests := []struct {
		name    string
		args    args
		wantErr bool
	}{
		// TODO: make this a single-case test or add a failing case.
		{
			name: "working",
			args: args{
				squashfs: "testdata/test.squashfs",
				fromDir:  "testdata/test.squashfs.addfiles",
				toDir:    "share/oem",
			},
			wantErr: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Copy squashfs file, so we can modify it without side effects.
			modify := tt.args.squashfs + ".mod"
			if err := pipe.Run(pipe.Exec("cp", tt.args.squashfs, modify)); err != nil {
				t.Fatalf("Failed to make a copy of %s", tt.args.squashfs)
			}
			// Run test on the new squashfs file.
			if err := pipe.Run(RebuildSquashFS(modify, tt.args.fromDir, tt.args.toDir)); (err != nil) != tt.wantErr {
				t.Errorf("RebuildSquashFS() error = %v, wantErr %v", err, tt.wantErr)
			}
			// List contents of the new and old files.
			newFields := listSquashfs(modify)
			origFields := listSquashfs(tt.args.squashfs)
			expectedFields := append(
				origFields,
				"squashfs-root/share/oem",
				"squashfs-root/share/oem/cloud-config.yml",
				"squashfs-root/share/oem/setup.sh",
			)
			// Check for differences.
			diff := pretty.Compare(expectedFields, newFields)
			if len(diff) != 0 {
				t.Errorf(diff)
			}
			// Remove modified file.
			if err := os.Remove(modify); err != nil {
				t.Errorf("RebuildSquashFS() error = %v, failed to remove %s", err, modify)
			}
		})
	}
}
