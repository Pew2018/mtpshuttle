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
