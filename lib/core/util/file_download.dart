// Saves/shares bytes as a file named [filename] (with MIME [mimeType]).
//
// On web this triggers a browser download via a Blob + anchor. On native
// platforms it writes the bytes to a temp file and presents the OS share sheet
// so the user chooses the destination (iOS "Save to Files", Android Downloads,
// AirDrop, mail, …) instead of dumping the file in a hidden app directory. The
// bytes are fetched through the authenticated ApiClient by the caller, so no
// object-store URL is ever exposed to the client (the storage endpoint is
// internal-only). Returns a [DownloadOutcome] so the caller can give feedback
// without surfacing an internal file path.
export 'file_download_types.dart';
export 'file_download_io.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
