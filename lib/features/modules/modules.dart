import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';

/// Dónde funciona un módulo.
enum Support { full, partial, none }

/// Un módulo de SmartBuds que puedes encender o apagar sin tocar el núcleo
/// (reproducción, voz y cerebro musical siempre están).
///
/// Límite honesto: Google Play y App Store no permiten que una app descargue
/// y ejecute código nuevo después de instalada. Por eso las extensiones vienen
/// dentro de la app y llegan con las actualizaciones; aquí eliges cuáles usar.
class SmartBudsModule {
  const SmartBudsModule({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.colors,
    required this.android,
    required this.iphone,
    this.permissions = const [],
    this.dependsOn = 'Nada externo',
    this.premium = false,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final List<Color> colors;
  final Support android;
  final Support iphone;
  final List<String> permissions;

  /// De qué servicio o API depende.
  final String dependsOn;

  /// Reservado para SmartBuds Premium. Hoy ninguno lo es: todo es gratis.
  final bool premium;
}

const smartBudsModules = <SmartBudsModule>[
  SmartBudsModule(
    id: 'knowledge',
    name: 'Conocimiento musical',
    description: '«Cuéntame de Feid»: resumen del artista, seguidores, parecidos y sus colaboraciones en tu música.',
    icon: Icons.menu_book_rounded,
    colors: AppColors.assistant,
    android: Support.full,
    iphone: Support.full,
    permissions: ['Internet'],
    dependsOn: 'Wikipedia (resumen) y Deezer (datos), gratis y sin clave',
  ),
  SmartBudsModule(
    id: 'social',
    name: 'Amigos',
    description: 'Enviar canciones, listas compartidas con votos y escuchar juntos.',
    icon: Icons.groups_rounded,
    colors: AppColors.music,
    android: Support.full,
    iphone: Support.full,
    permissions: ['Cuenta', 'Internet'],
    dependsOn: 'Supabase (tu cuenta)',
  ),
  SmartBudsModule(
    id: 'automations',
    name: 'Automatizaciones',
    description: 'Tus propios comandos y acciones al conectar audífonos o a una hora.',
    icon: Icons.auto_awesome_rounded,
    colors: AppColors.home,
    android: Support.full,
    iphone: Support.partial,
    permissions: ['Micrófono', 'Bluetooth'],
  ),
  SmartBudsModule(
    id: 'car',
    name: 'Modo carro',
    description: 'Pantalla grande y voz siempre activa; se abre sola con el Bluetooth del carro.',
    icon: Icons.directions_car_rounded,
    colors: AppColors.radio,
    android: Support.full,
    iphone: Support.partial,
    permissions: ['Micrófono', 'Bluetooth'],
  ),
  SmartBudsModule(
    id: 'visualizer',
    name: 'Visualizador en vivo',
    description: 'Barras que siguen la música real y carátula que respira con el ritmo.',
    icon: Icons.graphic_eq_rounded,
    colors: AppColors.stats,
    android: Support.partial,
    iphone: Support.none,
    permissions: ['Micrófono (ya concedido)', 'Ajustes de audio'],
    dependsOn: 'API Visualizer de Android (algunos fabricantes la bloquean)',
  ),
  SmartBudsModule(
    id: 'multidevice',
    name: 'Centro multidispositivo',
    description: 'Mira qué suena en tus otros teléfonos y continúa aquí.',
    icon: Icons.devices_rounded,
    colors: AppColors.devices,
    android: Support.full,
    iphone: Support.full,
    permissions: ['Cuenta', 'Internet'],
    dependsOn: 'Supabase (tu cuenta)',
  ),
  SmartBudsModule(
    id: 'smarthome',
    name: 'Hogar inteligente',
    description: 'Avisa a tu Home Assistant, IFTTT u otro servicio tuyo para cambiar luces y ambiente con la música.',
    icon: Icons.lightbulb_rounded,
    colors: AppColors.radio,
    android: Support.full,
    iphone: Support.full,
    permissions: ['Internet'],
    dependsOn: 'Un servicio tuyo con webhook (Home Assistant, IFTTT, Node-RED…)',
  ),
  SmartBudsModule(
    id: 'stats',
    name: 'Estadísticas avanzadas',
    description: 'Artistas por tiempo, rachas, horario y descubrimientos.',
    icon: Icons.insights_rounded,
    colors: AppColors.night,
    android: Support.full,
    iphone: Support.full,
  ),
];

SmartBudsModule moduleById(String id) => smartBudsModules.firstWhere((m) => m.id == id);
