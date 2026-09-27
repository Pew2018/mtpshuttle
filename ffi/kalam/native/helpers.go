package main

import (
	"fmt"
	"github.com/ganeshrvel/go-mtpfs/mtp"
	"github.com/ganeshrvel/go-mtpx"
	"log"
	"os"
	"sync/atomic"
)

var operationCancelled uint32

func checkOperationCancelled() error {
	if atomic.LoadUint32(&operationCancelled) != 0 {
		return fmt.Errorf("OperationCancelled")
	}
	return nil
}

func cancellableProgressCallback(next mtpx.ProgressCb) mtpx.ProgressCb {
	return func(info *mtpx.ProgressInfo, err error) error {
		if cancelErr := checkOperationCancelled(); cancelErr != nil {
			return cancelErr
		}
		if next == nil { return err }
		return next(info, err)
	}
}

func cancellableLocalPreprocessCallback(next mtpx.LocalPreprocessCb) mtpx.LocalPreprocessCb {
	return func(info *os.FileInfo, path string, err error) error {
		if cancelErr := checkOperationCancelled(); cancelErr != nil {
			return cancelErr
		}
		if next == nil { return err }
		return next(info, path, err)
	}
}

func cancellableMtpPreprocessCallback(next mtpx.MtpPreprocessCb) mtpx.MtpPreprocessCb {
	return func(info *mtpx.FileInfo, err error) error {
		if cancelErr := checkOperationCancelled(); cancelErr != nil {
			return cancelErr
		}
		if next == nil { return err }
		return next(info, err)
	}
}

func verifyMtpSession(c verifyMtpSessionMode) error {
	if container.dev == nil {
		return fmt.Errorf("ErrorMtpDetectFailed")
	}

	if !c.skipDeviceChangeCheck && container.deviceInfo != nil {
		dInfo, err := mtpx.FetchDeviceInfo(container.dev)
		if err != nil {
			container.deviceInfo = nil

			_ = _dispose()

			return err
		}

		if container.deviceInfo.SerialNumber != dInfo.SerialNumber {
			container.deviceInfo = dInfo

			return fmt.Errorf("ErrorDeviceChanged")
		}
	}

	return nil
}

func _initialize(i mtpx.Init) (*mtp.Device, error) {
	d, err := mtpx.Initialize(i)
	if err != nil {
		return nil, err
	}

	container.dev = d

	return d, nil
}

func _fetchDeviceInfo() (*mtp.DeviceInfo, error) {
	v := verifyMtpSessionMode{skipDeviceChangeCheck: true}

	if !v.skipDeviceChangeCheck {
		return fmt.Errorf("'skipDeviceChangeCheck' must be true in _fetchDeviceInfo")
	}

	if err := verifyMtpSession(v); err != nil {
		return nil, err
	}

	dInfo, err := mtpx.FetchDeviceInfo(container.dev)
	if err != nil {
		container.deviceInfo = nil

		return nil, err
	}

	container.deviceInfo = dInfo

	return dInfo, nil
}

func _fetchStorages() ([]mtpx.StorageData, error) {
	if err := verifyMtpSession(verifyMtpSessionMode{}); err != nil {
		return nil, err
	}

	storages, err := mtpx.FetchStorages(container.dev)
	if err != nil {
		return nil, err
	}

	return storages, nil
}

func _makeDirectory(storageId uint32, fullPath string) error {
	if err := verifyMtpSession(verifyMtpSessionMode{}); err != nil {
		return err
	}

	_, err := mtpx.MakeDirectory(container.dev, storageId, fullPath)
	if err != nil {
		return err
	}

	return nil
}

func _fileExists(storageId uint32, fileProps []mtpx.FileProp) (exists []mtpx.FileExistsContainer, error error) {
	if err := verifyMtpSession(verifyMtpSessionMode{}); err != nil {
		return []mtpx.FileExistsContainer{}, err
	}

	exists, err := mtpx.FileExists(container.dev, storageId, fileProps)
	if err != nil {
		return exists, err
	}

	return exists, nil
}

func _deleteFile(storageId uint32, fileProps []mtpx.FileProp) (error error) {
	if err := verifyMtpSession(verifyMtpSessionMode{}); err != nil {
		return err
	}

	err := mtpx.DeleteFile(container.dev, storageId, fileProps)
	if err != nil {
		return err
	}

	return nil
}

func _renameFile(storageId uint32, fileProp mtpx.FileProp, newFileName string) (error error) {
	if err := verifyMtpSession(verifyMtpSessionMode{}); err != nil {
		return err
	}

	_, err := mtpx.RenameFile(container.dev, storageId, fileProp, newFileName)
	if err != nil {
		return err
	}

	return nil
}

func _walk(storageId uint32, fullPath string, recursive, skipDisallowedFiles, skipHiddenFiles bool, onEntry func(*mtpx.FileInfo)) (files []*mtpx.FileInfo, err error) {
	if err := verifyMtpSession(verifyMtpSessionMode{}); err != nil {
		return []*mtpx.FileInfo{}, err
	}

	_, _, _, err = mtpx.Walk(container.dev, storageId, fullPath, recursive, skipDisallowedFiles, skipHiddenFiles, func(objectId uint32, fi *mtpx.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if err := checkOperationCancelled(); err != nil { return err }

		files = append(files, fi)
		if onEntry != nil { onEntry(fi) }

		return nil
	})
	if err != nil {
		return []*mtpx.FileInfo{}, err
	}

	return files, nil
}

func _uploadFiles(storageId uint32, sources []string, destination string, preprocessFiles bool, preprocessCb mtpx.LocalPreprocessCb, progressCb mtpx.ProgressCb) (err error) {
	if err := checkOperationCancelled(); err != nil {
		return err
	}
	if err := verifyMtpSession(verifyMtpSessionMode{}); err != nil {
		return err
	}

	_, _, _, err = mtpx.UploadFiles(
		container.dev, storageId, sources, destination, preprocessFiles,
		cancellableLocalPreprocessCallback(preprocessCb),
		cancellableProgressCallback(progressCb),
	)
	if err != nil {
		return err
	}

	return nil
}

func _downloadFiles(storageId uint32, sources []string, destination string, preprocessFiles bool, preprocessCb mtpx.MtpPreprocessCb, progressCb mtpx.ProgressCb) (err error) {
	if err := checkOperationCancelled(); err != nil {
		return err
	}
	if err := verifyMtpSession(verifyMtpSessionMode{}); err != nil {
		return err
	}

	_, _, err = mtpx.DownloadFiles(
		container.dev, storageId, sources, destination, preprocessFiles,
		cancellableMtpPreprocessCallback(preprocessCb),
		cancellableProgressCallback(progressCb),
	)
	if err != nil {
		return err
	}

	return nil
}

func _dispose() error {
	if container.dev == nil {
		return nil
	}

	mtpx.Dispose(container.dev)

	return nil
}

func lockMtp() error {
	if container.locked {
		return fmt.Errorf("ErrorMtpLockExists")
	}

	container.locked = true

	defer func() {
		container.locked = false
	}()

	return nil
}
