package main

import (
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"

	"github.com/ganeshrvel/go-mtpx"
)

func TestCancellableCallbacksStopWhenOperationIsCancelled(t *testing.T) {
	atomic.StoreUint32(&operationCancelled, 0)
	defer atomic.StoreUint32(&operationCancelled, 0)

	progressCalled := false
	progress := cancellableProgressCallback(func(*mtpx.ProgressInfo, error) error {
		progressCalled = true
		return nil
	})
	if err := progress(&mtpx.ProgressInfo{}, nil); err != nil {
		t.Fatalf("uncancelled progress callback returned error: %v", err)
	}
	if !progressCalled {
		t.Fatal("uncancelled progress callback was not forwarded")
	}

	atomic.StoreUint32(&operationCancelled, 1)
	progressCalled = false
	if err := progress(&mtpx.ProgressInfo{}, nil); err == nil || err.Error() != "OperationCancelled" {
		t.Fatalf("cancelled progress callback returned %v, want OperationCancelled", err)
	}
	if progressCalled {
		t.Fatal("cancelled progress callback was forwarded")
	}

	if err := cancellableLocalPreprocessCallback(nil)(nil, "", nil); err == nil || err.Error() != "OperationCancelled" {
		t.Fatalf("cancelled upload preprocessing returned %v, want OperationCancelled", err)
	}
	if err := cancellableMtpPreprocessCallback(nil)(nil, nil); err == nil || err.Error() != "OperationCancelled" {
		t.Fatalf("cancelled download preprocessing returned %v, want OperationCancelled", err)
	}
}

func TestSnapshotProgressInfoCopiesNestedTransferState(t *testing.T) {
	original := &mtpx.ProgressInfo{
		FileInfo:       &mtpx.FileInfo{Name: "before"},
		ActiveFileSize: &mtpx.TransferSizeInfo{Sent: 1},
		BulkFileSize:   &mtpx.TransferSizeInfo{Sent: 2},
	}
	snapshot := snapshotProgressInfo(original)
	if snapshot == original ||
		snapshot.FileInfo == original.FileInfo ||
		snapshot.ActiveFileSize == original.ActiveFileSize ||
		snapshot.BulkFileSize == original.BulkFileSize {
		t.Fatal("snapshot retained pointers to mutable transfer state")
	}

	original.FileInfo.Name = "after"
	original.ActiveFileSize.Sent = 10
	original.BulkFileSize.Sent = 20
	if snapshot.FileInfo.Name != "before" ||
		snapshot.ActiveFileSize.Sent != 1 ||
		snapshot.BulkFileSize.Sent != 2 {
		t.Fatal("snapshot changed when the transfer library updated its progress")
	}
}

func TestVerifyDownloadedFilesRequiresCompleteMatchingEntries(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "folder")
	if err := os.Mkdir(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(dir, "photo.jpg")
	if err := os.WriteFile(file, []byte("complete"), 0o600); err != nil {
		t.Fatal(err)
	}

	entries := []downloadIntegrityEntry{
		{localPath: dir, isDir: true},
		{localPath: file, size: int64(len("complete"))},
	}
	if err := verifyDownloadedFiles(entries); err != nil {
		t.Fatalf("complete download rejected: %v", err)
	}

	if err := os.WriteFile(file, []byte("short"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := verifyDownloadedFiles(entries); err == nil {
		t.Fatal("short download was accepted")
	}

	if err := os.Remove(file); err != nil {
		t.Fatal(err)
	}
	if err := verifyDownloadedFiles(entries); err == nil {
		t.Fatal("missing download was accepted")
	}
}
