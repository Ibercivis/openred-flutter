import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../l10n/app_localizations.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String _kRadiationIconAsset = 'assets/icons/radioactive.svg';

  bool _isSpanish(BuildContext context) {
    return Localizations.localeOf(context).languageCode.toLowerCase() == 'es';
  }

  String _aboutRadiationText(BuildContext context) {
    final isEs = _isSpanish(context);
    if (isEs) {
      return 'Radiación (ionizante)\n\n'
          'En este proyecto el mapa agrega medidas de tasa de dosis (µSv/h) y/o CPM según el dispositivo. '
          'Los valores dependen del sensor, su calibración y las condiciones de medida. '
          'Interpreta siempre los datos como orientativos, especialmente en interiores y cerca de fuentes puntuales.';
    }
    return 'Radiation (ionizing)\n\n'
        'This project aggregates dose-rate (µSv/h) and/or CPM depending on the device. '
        'Values depend on the sensor, calibration, and measurement conditions. '
        'Treat data as indicative, especially indoors and near point sources.';
  }

  String _aboutLightPollutionText(BuildContext context) {
    final isEs = _isSpanish(context);
    if (isEs) {
      return 'Contaminación lumínica\n\n'
          'En el mapa de “Light pollution” asumimos que el valor agregado (avg) es lux. '
          'Para visualizarlo, se usa una escala 0–20 lux (a partir de 20 satura) con colores azul→púrpura→rojo. '
          'La interpretación depende del entorno (farolas, luna, nubes, orientación del sensor).';
    }
    return 'Light pollution\n\n'
        'In the “Light pollution” map we assume the aggregated avg value is lux. '
        'Visualization uses a 0–20 lux scale (saturates above 20) with a blue→purple→red palette. '
        'Interpretation depends heavily on the environment (streetlights, moon, clouds, sensor orientation).';
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final l10n = AppLocalizations.of(context);
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.aboutOpenUrlFailed(url)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openTelegram(BuildContext context) async {
    await _openUrl(context, Config.telegramCommunityUrl);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Open-red'),
            Text(
              l10n.navAbout,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.aboutBody,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          Card(
            child: ExpansionTile(
              leading: SvgPicture.asset(
                _kRadiationIconAsset,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(
                  IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface,
                  BlendMode.srcIn,
                ),
                semanticsLabel: 'Radiation',
              ),
              title: Text(_isSpanish(context) ? 'Acerca de la radiación' : 'About radiation'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  _aboutRadiationText(context),
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.nightlight_round),
              title: Text(_isSpanish(context) ? 'Acerca de la contaminación lumínica' : 'About light pollution'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  _aboutLightPollutionText(context),
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.public),
              title: Text(l10n.aboutProjectWebpage),
              subtitle: const Text('https://open-red.es'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => unawaited(_openUrl(context, 'https://open-red.es')),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.map_outlined),
              title: Text(l10n.aboutProjectMap),
              subtitle: const Text('https://map.open-red.es'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => unawaited(_openUrl(context, 'https://map.open-red.es')),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.send, color: Colors.lightBlueAccent),
              title: Text(l10n.aboutCommunityTelegram),
              subtitle: Text(Config.telegramCommunityUrl),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => unawaited(_openTelegram(context)),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              l10n.aboutDevelopedBy,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
