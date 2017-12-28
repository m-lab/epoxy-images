package main

import (
	"os"
	"path"
	"testing"
)

func Test_buildCustomImage(t *testing.T) {
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
		{
			name: "working",
			args: args{
				vmlinuzURL: "testdata/example.vmlinuz",
				initramURL: "testdata/example.cpio.gz",
				resources:  "testdata/example.squashfs.addfiles",
				customName: "testdata/new.cpio.gz",
			},
			wantErr: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cwd, err := os.Getwd()
			if err != nil {
				t.Fatalf("build %v", err)
			}
			if err := buildCustomImage(
				path.Join("file://", cwd, tt.args.vmlinuzURL),
				path.Join("file://", cwd, tt.args.initramURL),
				path.Join(cwd, tt.args.resources),
				path.Join(cwd, tt.args.customName)); (err != nil) != tt.wantErr {
				t.Errorf("buildCustomImage() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}
