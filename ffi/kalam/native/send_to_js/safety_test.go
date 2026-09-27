package send_to_js

import (
	"testing"

	"github.com/ganeshrvel/go-mtpx"
)

func TestSerializersIgnoreMalformedOptionalPayloads(t *testing.T) {
	SendFileExists(nil, []mtpx.FileExistsContainer{{Exists: true}, {Exists: false}}, []string{"only-one"})
	SendWalk(nil, []*mtpx.FileInfo{nil})
	SendUploadFilesPreprocess(nil, nil, "")
	SendDownloadFilesPreprocess(nil, nil)
	SendTransferFilesProgress(nil, nil)
	SendTransferFilesProgress(nil, &mtpx.ProgressInfo{})
}
