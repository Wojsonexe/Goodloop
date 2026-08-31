import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final double radius;
  final bool showLoader;

  const UserAvatar({
    super.key,
    required this.photoUrl,
    this.radius = 28,
    this.showLoader = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (photoUrl != null && photoUrl!.isNotEmpty)
            ClipOval(
              child: CachedNetworkImage(
                imageUrl: photoUrl!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                placeholder: (c, _) =>
                    const CircularProgressIndicator(strokeWidth: 2),
                errorWidget: (c, _, __) => Icon(Icons.person, size: radius),
              ),
            )
          else
            Icon(Icons.person, size: radius),
          if (showLoader)
            Container(
              width: radius * 2,
              height: radius * 2,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black54,
              ),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
