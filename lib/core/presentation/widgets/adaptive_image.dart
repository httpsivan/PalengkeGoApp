import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palengkego/core/utils/image_url_resolver.dart';

class AdaptiveImage extends StatelessWidget {
  final String? path;
  final String? fallbackPath;
  final BoxFit fit;
  final Widget? placeholder;
  final double? width;
  final double? height;

  const AdaptiveImage(
    this.path, {
    super.key,
    this.fallbackPath,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.width,
    this.height,
  });

  /// In-memory cache for decoded base64 image bytes to preserve
  /// reference identity across widget rebuilds and eliminate blinking/flickering.
  static final Map<String, Uint8List> _base64Cache = {};

  static Uint8List? getOrDecodeBase64(String path) {
    final cached = _base64Cache[path];
    if (cached != null) return cached;
    try {
      final commaIndex = path.indexOf(',');
      final b64String = commaIndex != -1 ? path.substring(commaIndex + 1) : path;
      final bytes = base64Decode(b64String.replaceAll(RegExp(r'\s+'), ''));
      if (_base64Cache.length >= 60) {
        _base64Cache.remove(_base64Cache.keys.first);
      }
      _base64Cache[path] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedPath = resolveImageUrl(path);
    if (resolvedPath == null || resolvedPath.isEmpty) {
      if (fallbackPath != null && fallbackPath!.isNotEmpty) {
        return AdaptiveImage(
          fallbackPath,
          fit: fit,
          width: width,
          height: height,
          placeholder: placeholder,
        );
      }
      return _buildPlaceholder();
    }

    if (resolvedPath.startsWith('data:image/')) {
      final bytes = getOrDecodeBase64(resolvedPath);
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: fit,
          width: width,
          height: height,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        );
      }
      return _buildPlaceholder();
    }

    if (resolvedPath.startsWith('assets/')) {
      return Image.asset(
        resolvedPath,
        fit: fit,
        width: width,
        height: height,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }

    if (resolvedPath.startsWith('http://') || resolvedPath.startsWith('https://')) {
      if (kIsWeb) {
        return Image.network(
          resolvedPath,
          fit: fit,
          width: width,
          height: height,
          gaplessPlayback: true,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _buildPlaceholder(isLoading: true);
          },
          errorBuilder: (context, error, stackTrace) {
            if (resolvedPath.contains('drive.google.com') ||
                resolvedPath.contains('googleusercontent.com')) {
              final idMatch = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(resolvedPath) ??
                  RegExp(r'/d/([a-zA-Z0-9_-]+)').firstMatch(resolvedPath);
              if (idMatch != null) {
                final fileId = idMatch.group(1);
                final altUrl = resolvedPath.contains('thumbnail')
                    ? 'https://lh3.googleusercontent.com/d/$fileId'
                    : 'https://drive.google.com/thumbnail?sz=w1000&id=$fileId';
                if (altUrl != resolvedPath) {
                  return AdaptiveImage(
                    altUrl,
                    fallbackPath: fallbackPath,
                    fit: fit,
                    width: width,
                    height: height,
                    placeholder: placeholder,
                  );
                }
              }
            }
            if (fallbackPath != null &&
                fallbackPath!.isNotEmpty &&
                fallbackPath != resolvedPath) {
              return AdaptiveImage(
                fallbackPath,
                fit: fit,
                width: width,
                height: height,
                placeholder: placeholder,
              );
            }
            return _buildPlaceholder();
          },
        );
      }
      return CachedNetworkImage(
        imageUrl: resolvedPath,
        fit: fit,
        width: width,
        height: height,
        placeholder: (context, url) => _buildPlaceholder(isLoading: true),
        errorWidget: (context, url, error) {
          // If this was a Google Drive URL, try alternative drive CDN endpoints
          if (resolvedPath.contains('drive.google.com') ||
              resolvedPath.contains('googleusercontent.com')) {
            final idMatch = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(resolvedPath) ??
                RegExp(r'/d/([a-zA-Z0-9_-]+)').firstMatch(resolvedPath);
            if (idMatch != null) {
              final fileId = idMatch.group(1);
              final altUrl = resolvedPath.contains('thumbnail')
                  ? 'https://lh3.googleusercontent.com/d/$fileId'
                  : 'https://drive.google.com/thumbnail?sz=w1000&id=$fileId';
              return CachedNetworkImage(
                imageUrl: altUrl,
                fit: fit,
                width: width,
                height: height,
                placeholder: (context, url) => _buildPlaceholder(isLoading: true),
                errorWidget: (context, url, error) {
                  final ucUrl = 'https://drive.google.com/uc?export=view&id=$fileId';
                  return CachedNetworkImage(
                    imageUrl: ucUrl,
                    fit: fit,
                    width: width,
                    height: height,
                    placeholder: (context, url) => _buildPlaceholder(isLoading: true),
                    errorWidget: (context, url, error) {
                      if (fallbackPath != null && fallbackPath!.isNotEmpty && fallbackPath != resolvedPath) {
                        return AdaptiveImage(
                          fallbackPath,
                          fit: fit,
                          width: width,
                          height: height,
                          placeholder: placeholder,
                        );
                      }
                      return _buildPlaceholder();
                    },
                  );
                },
              );
            }
          }
          if (fallbackPath != null && fallbackPath!.isNotEmpty && fallbackPath != resolvedPath) {
            return AdaptiveImage(
              fallbackPath,
              fit: fit,
              width: width,
              height: height,
              placeholder: placeholder,
            );
          }
          return _buildPlaceholder();
        },
      );
    }

    if (kIsWeb) {
      // On web, local paths picked by image_picker are blob URLs. We can use Image.network
      return Image.network(
        resolvedPath,
        fit: fit,
        width: width,
        height: height,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    } else {
      final file = resolvedPath.startsWith('file:')
          ? (resolvedPath.startsWith('file://')
              ? File.fromUri(Uri.parse(resolvedPath))
              : File(resolvedPath.substring(5)))
          : File(resolvedPath);
      bool fileValid = false;
      try {
        fileValid = file.existsSync() && file.lengthSync() > 0;
      } catch (_) {
        fileValid = false;
      }
      if (!fileValid) {
        if (fallbackPath != null && fallbackPath!.isNotEmpty && fallbackPath != resolvedPath) {
          return AdaptiveImage(
            fallbackPath,
            fit: fit,
            width: width,
            height: height,
            placeholder: placeholder,
          );
        }
        return _buildPlaceholder();
      }
      return Image.file(
        file,
        fit: fit,
        width: width,
        height: height,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          if (fallbackPath != null && fallbackPath!.isNotEmpty && fallbackPath != resolvedPath) {
            return AdaptiveImage(
              fallbackPath,
              fit: fit,
              width: width,
              height: height,
              placeholder: placeholder,
            );
          }
          return _buildPlaceholder();
        },
      );
    }
  }

  Widget _buildPlaceholder({bool isLoading = false}) {
    if (placeholder != null) return placeholder!;

    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: Center(
        child: isLoading
            ? const CircularProgressIndicator(strokeWidth: 2)
            : const Icon(Icons.image_outlined, color: Colors.grey),
      ),
    );
  }
}

/// Helper for DecorationImage usage
ImageProvider? adaptiveImageProvider(String? path) {
  final resolvedPath = resolveImageUrl(path);
  if (resolvedPath == null || resolvedPath.isEmpty) {
    return null;
  }
  if (resolvedPath.startsWith('data:image/')) {
    final bytes = AdaptiveImage.getOrDecodeBase64(resolvedPath);
    if (bytes != null) {
      return MemoryImage(bytes);
    }
    return null;
  }
  if (resolvedPath.startsWith('assets/')) {
    return AssetImage(resolvedPath);
  }
  if (resolvedPath.startsWith('http://') || resolvedPath.startsWith('https://')) {
    if (kIsWeb) {
      return NetworkImage(resolvedPath);
    }
    return CachedNetworkImageProvider(resolvedPath);
  }
  if (kIsWeb) {
    return NetworkImage(resolvedPath);
  } else {
    final file = resolvedPath.startsWith('file://')
        ? File.fromUri(Uri.parse(resolvedPath))
        : File(resolvedPath);
    try {
      if (file.existsSync() && file.lengthSync() > 0) {
        return FileImage(file);
      }
    } catch (_) {}
    return null;
  }
}
