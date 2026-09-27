package main

import (
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
