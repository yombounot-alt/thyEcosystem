import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:thy_design_system/thy_design_system.dart';

import '../../../l10n/app_localizations.dart';

class _OnboardingPage {
  const _OnboardingPage(this.title, this.icon);
  final String title;
  final IconData icon;
}

/// Only promises the app keeps today (an "AI assistant" page was removed: not built yet).
List<_OnboardingPage> _pages(AppLocalizations t) => [
  _OnboardingPage(t.onboardingManage, Icons.storefront_outlined),
  _OnboardingPage(t.onboardingTrack, Icons.inventory_2_outlined),
  _OnboardingPage(t.onboardingProfit, Icons.trending_up),
  _OnboardingPage(t.onboardingOffline, Icons.cloud_off_outlined),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final pages = _pages(t);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    final page = pages[i];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(page.icon, size: 96, color: context.colors.primary),
                        const SizedBox(height: 32),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  pages.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? context.colors.primary : context.colors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              PrimaryButton(label: t.onboardingStart, onPressed: () => context.go('/phone')),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
