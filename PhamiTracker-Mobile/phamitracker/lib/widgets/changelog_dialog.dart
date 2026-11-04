import 'package:flutter/material.dart';

import '../services/changelog_service.dart';
import '../theme/app_theme.dart';

/// "About PhamiTracker" → every release and what changed, newest first (like PhamiJam's).
Future<void> showChangelogDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _ChangelogDialog());
}

class _ChangelogDialog extends StatelessWidget {
  const _ChangelogDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Version History', style: AppText.display(22)),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: FutureBuilder<List<ChangelogEntry>>(
          future: ChangelogService.load(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snapshot.data ?? const [];
            if (entries.isEmpty) {
              return const Center(
                child: Text("Couldn't load version history.", style: TextStyle(color: AppColors.textDim)),
              );
            }
            return ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 28, color: AppColors.border),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.date.isEmpty ? entry.version : '${entry.version} — ${entry.date}',
                      style: AppText.display(16, color: index == 0 ? AppColors.goal : AppColors.text),
                    ),
                    const SizedBox(height: 8),
                    for (final change in entry.changes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•  ', style: TextStyle(color: AppColors.textDim)),
                            Expanded(
                              child: Text(change, style: const TextStyle(color: AppColors.textDim, height: 1.35)),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
