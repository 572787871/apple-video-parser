import 'package:flutter/material.dart';

import '../services/ui_state.dart';
import '../widgets/app_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
          children: [
            AppCard(
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xff2563eb), Color(0xff7c3aed)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.folder_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '默认保存路径',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 4),
                        Text('文件 App / 本 App / Documents / videos'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: SwitchListTile(
                value: state.onlyWifi,
                onChanged: state.toggleWifi,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '仅 Wi-Fi 下载',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('避免移动网络消耗过多流量'),
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cleaning_services_rounded),
                    title: const Text('清理缓存'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {},
                  ),
                  Divider(color: scheme.outlineVariant),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('关于 App'),
                    subtitle: const Text('网页视频解析下载器 1.0.0'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_outlined, color: scheme.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '合规提示：仅下载自己有权访问的视频内容。本 App 不绕过 DRM、付费墙或加密版权保护。',
                      style: TextStyle(height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
