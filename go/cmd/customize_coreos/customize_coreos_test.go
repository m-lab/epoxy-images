package main

import (
	"os"
	"path"
	"testing"
)

func Test_buildCustomImage(t *testing.T) {
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf("build %v", err)
	}
	type args struct {
		vmlinuzURL string
		initramURL string
		resources  string
		customName string
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
				vmlinuzURL: path.Join("file://", cwd, "testdata/example.vmlinuz"),
				initramURL: path.Join("file://", cwd, "testdata/example.cpio.gz"),
				resources:  path.Join(cwd, "testdata/example.squashfs.addfiles"),
				customName: path.Join(cwd, "testdata/new.cpio.gz"),
			},
			wantErr: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := buildCustomImage(
				tt.args.vmlinuzURL,
				tt.args.initramURL,
				tt.args.resources,
				tt.args.customName); (err != nil) != tt.wantErr {
				t.Errorf("buildCustomImage() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}
