// Platform bridge for voice comments. Two operations differ between native and
// web and are implemented per platform:
//
//  • [readRecordedAudio] — after `record` finishes, turn the recorder's output
//    handle into raw bytes + the real MIME type. Native returns a file path;
//    web returns a `blob:` URL that must be fetched back.
//  • [createPlayableSource] — turn downloaded audio bytes into a URI `just_audio`
//    can play: a temp file on native, a `blob:` object URL on web. The returned
//    `dispose` frees it (deletes the file / revokes the object URL).
export 'voice_platform_io.dart'
    if (dart.library.js_interop) 'voice_platform_web.dart';
