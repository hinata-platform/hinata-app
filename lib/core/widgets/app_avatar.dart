import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../api/api_client.dart';
import '../theme/app_colors.dart';

/// Process-wide cache of fetched avatar bytes, keyed by the (cache-busted)
/// avatar URL. `null` marks a URL that failed / 404'd so we don't refetch it on
/// every rebuild. Because avatar URLs carry a `?v=` token that changes on each
/// upload, a new picture is always a new key (no stale image).
final Map<String, Uint8List?> _avatarBytesCache = {};
final Map<String, Future<void>> _avatarInFlight = {};

/// Circular avatar with deterministic pastel background and initials fallback.
///
/// Server avatar URLs are loaded through the authenticated [ApiClient] (XHR) and
/// rendered from bytes via [Image.memory] — *not* [NetworkImage]. This is the
/// same approach the org-logo uses and it is what makes avatars actually show
/// on Flutter **web**: a cross-origin `<img>` drawn by CanvasKit taints the
/// canvas without CORS headers and silently fails, whereas decoded bytes render
/// everywhere. It also transparently carries the bearer token + the
/// ngrok-skip header, so it works behind auth and tunnels too.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 18,
  });

  final String name;
  final String? imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) return _circle(null);

    // External absolute images (not our API) keep the plain network path.
    if (url.startsWith('http') && !url.contains('/api/v1/users/')) {
      return _circle(NetworkImage(url));
    }

    ApiClient? api;
    try {
      api = context.read<ApiClient>();
    } catch (_) {
      // No ApiClient in scope (e.g. widget tests) — show initials.
      return _circle(null);
    }
    return ApiImageAvatar(
      key: ValueKey(url),
      path: url,
      api: api,
      placeholder: _circle(null),
      builder: _circle,
    );
  }

  Widget _circle(ImageProvider? image) => CircleAvatar(
    radius: radius,
    backgroundColor: AppColors.pastelFor(name.hashCode.abs()),
    // Decode at (roughly) the on-screen pixel size, not the source's full
    // resolution: a 512px upload rendered in a 28-36px circle otherwise
    // wastes decode time and GPU texture memory — costly in avatar-dense
    // lists (member strips, notifications, boards). 3x covers the densest
    // screens; ResizeImage is a no-op when the source is already smaller.
    foregroundImage: image == null
        ? null
        : ResizeImage(
            image,
            width: (radius * 2 * 3).round(),
            height: (radius * 2 * 3).round(),
          ),
    child: Text(
      _initials(name),
      style: TextStyle(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: radius * 0.8,
      ),
    ),
  );

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

/// Loads avatar bytes for [path] (relative to the API base) once, caches them,
/// and renders them with [Image.memory]; shows [placeholder] while loading or
/// on failure.
class ApiImageAvatar extends StatefulWidget {
  const ApiImageAvatar({
    super.key,
    required this.path,
    required this.api,
    required this.placeholder,
    required this.builder,
  });

  final String path;
  final ApiClient api;
  final Widget placeholder;
  final Widget Function(ImageProvider? image) builder;

  @override
  State<ApiImageAvatar> createState() => ApiImageAvatarState();
}

class ApiImageAvatarState extends State<ApiImageAvatar> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final path = widget.path;
    if (_avatarBytesCache.containsKey(path)) {
      _bytes = _avatarBytesCache[path];
      return;
    }
    // Coalesce concurrent loads of the same URL (e.g. avatar shown twice).
    final pending = _avatarInFlight[path] ??= _fetch(path);
    await pending;
    if (mounted) setState(() => _bytes = _avatarBytesCache[path]);
  }

  Future<void> _fetch(String path) async {
    try {
      final result = await widget.api.getBytes(path);
      _avatarBytesCache[path] = result == null
          ? null
          : Uint8List.fromList(result.bytes);
    } catch (_) {
      _avatarBytesCache[path] = null;
    } finally {
      _avatarInFlight.remove(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return widget.placeholder;
    return widget.builder(MemoryImage(bytes));
  }
}

/// Overlapping avatar stack like the member group in the design header.
class AvatarStack extends StatelessWidget {
  const AvatarStack({
    super.key,
    required this.names,
    this.max = 3,
    this.radius = 14,
  });

  final List<String> names;
  final int max;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final visible = names.take(max).toList();
    final overflow = names.length - visible.length;
    return SizedBox(
      height: radius * 2,
      width: visible.isEmpty
          ? 0
          : radius * 2 +
                (visible.length - 1 + (overflow > 0 ? 1 : 0)) * radius * 1.2,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * radius * 1.2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: AppAvatar(name: visible[i], radius: radius),
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: visible.length * radius * 1.2,
              child: CircleAvatar(
                radius: radius,
                backgroundColor: AppColors.navy,
                child: Text(
                  '+$overflow',
                  style: TextStyle(color: Colors.white, fontSize: radius * 0.7),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
