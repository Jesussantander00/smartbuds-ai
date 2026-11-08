import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/voice_engine/voice_engine.dart';

/// Asistente: qué puedes decir y cómo responde SmartBuds.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    super.key,
    required this.settings,
    this.voice,
    this.onHeadphoneTapsChanged,
  });

  final AppSettings settings;
  final VoiceEngine? voice;

  /// Avisa al lado nativo (Android) de que se activaron/desactivaron los toques.
  final ValueChanged<bool>? onHeadphoneTapsChanged;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  AppSettings get settings => widget.settings;
  VoiceEngine? get voice => widget.voice;
  bool _speakerAvailable = false;

  @override
  void initState() {
    super.initState();
    voice?.speakerAvailable().then((v) {
      if (mounted) setState(() => _speakerAvailable = v);
    });
  }

  static const _commands = <(String, String)>[
    ('«Cambia»', 'Siguiente canción'),
    ('«Devuelve»', 'Canción anterior'),
    ('«Pausa» / «Continúa»', 'Pausar o seguir'),
    ('«Sube» / «Baja»', 'Volumen'),
    ('«Busca»', 'Te pregunta «¿Qué canción?» y la reproduce'),
    ('«Oye música»', 'Responde «¿Sí?»: di lo que quieras, p. ej. «busca Ojalá de Ryan Castro»'),
    ('«Me gusta»', 'Guarda la canción en tus favoritas'),
    ('«No me gusta»', 'La baja en tu perfil y la cambia'),
    ('«Pon algo que me guste»', 'Elige una de tus favoritas según la hora'),
    ('«Pon algo nuevo»', 'Canciones que no conoces de tus artistas'),
    ('«Pon algo de»', 'Te pregunta «¿De quién?» y pone música de ese artista'),
    ('«Pon algo para entrenar»', 'También: tranquilo, de fiesta, para dormir, para estudiar'),
    ('«Pon …» (sin música)', 'Si no suena nada: «pon Ojalá de Ryan Castro» directo'),
    ('«¿Qué suena?»', 'Te dice el nombre de la canción'),
    ('«Repite» / «Otra vez»', 'La canción desde el principio'),
    ('«Adelanta» / «Atrasa»', '30 segundos adelante o atrás'),
    ('«Apaga en veinte minutos»', 'Temporizador: baja el volumen y pausa. «Cancela el temporizador»'),
    ('«Deshacer»', 'Vuelve a la canción de antes, donde iba'),
    ('«Comparte esta»', 'Prepara el enlace para WhatsApp'),
    ('«Pon mi radio»', 'Música sin parar: favoritas y descubrimientos'),
  ];

  Future<void> _editWake(BuildContext context) async {
    final settings = widget.settings;
    final ctrl = TextEditingController(text: settings.wakePhrase);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tu palabra de activación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Usa dos palabras comunes en español, por ejemplo «hola amigo» '
                'u «oye parce». Nombres raros o en inglés pueden no reconocerse.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'hola amigo',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Quitar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value == null) return;
    settings.update(wakePhrase: value);
    await widget.voice?.setCustomWake(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Asistente')),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, if (voice != null) voice!]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Lo que puedes decir', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('Di la orden sola, con una pequeña pausa antes y después. '
                'Hablar o cantar normal no dispara nada.'),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final (say, does) in _commands)
                    ListTile(dense: true, title: Text(say), subtitle: Text(does)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Ajustes', style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              title: const Text('Respuesta por voz'),
              subtitle: const Text('SmartBuds te confirma al oído: «Reproduciendo…»'),
              value: settings.voiceFeedback,
              onChanged: (v) {
                settings.update(voiceFeedback: v);
                voice?.feedbackEnabled = v;
              },
            ),
            SwitchListTile(
              title: const Text('Seguir a mis audífonos'),
              subtitle: const Text(
                  'Pausa la escucha al quitarte los audífonos y la reanuda al conectarlos'),
              value: settings.followHeadphones,
              onChanged: (v) {
                settings.update(followHeadphones: v);
                voice?.followHeadphones = v;
              },
            ),
            SwitchListTile(
              title: const Text('Solo con «Oye música»'),
              subtitle: const Text('SmartBuds solo obedece después de que digas «Oye música». '
                  'Casi nunca se activa por error.'),
              value: settings.wakeWord,
              onChanged: (v) {
                settings.update(wakeWord: v);
                voice?.requireWakeWord = v;
              },
            ),
            SwitchListTile(
              title: const Text('Toques en los audífonos'),
              subtitle: const Text('Dos toques: siguiente canción. Tres toques: la anterior. '
                  'Funciona con cualquier audífono con botón.'),
              value: settings.headphoneTaps,
              onChanged: (v) {
                settings.update(headphoneTaps: v);
                widget.onHeadphoneTapsChanged?.call(v);
              },
            ),
            SwitchListTile(
              title: const Text('Radio SmartBuds'),
              subtitle: const Text('Cuando termina una canción, SmartBuds elige la siguiente.'),
              value: settings.radioMode,
              onChanged: (v) => settings.update(radioMode: v),
            ),
            SwitchListTile(
              title: const Text('Anunciar cada canción'),
              subtitle: const Text('Dice suavemente el nombre de la canción nueva.'),
              value: settings.announceSongs,
              onChanged: (v) => settings.update(announceSongs: v),
            ),
            SwitchListTile(
              title: const Text('Retomar al conectar audífonos'),
              subtitle: const Text('La música sigue donde la dejaste.'),
              value: settings.resumeOnHeadphones,
              onChanged: (v) => settings.update(resumeOnHeadphones: v),
            ),
            ListTile(
              leading: const Icon(Icons.campaign),
              title: const Text('Tu palabra de activación'),
              subtitle: Text(settings.wakePhrase.isEmpty
                  ? 'Además de «Oye música». Toca para elegir una.'
                  : '«${settings.wakePhrase}» (y también «Oye música»)'),
              onTap: () => _editWake(context),
            ),
            SwitchListTile(
              title: const Text('Enviar reportes de errores'),
              subtitle: const Text('Anónimos: solo el tipo de error, nunca tu voz ni lo que dices.'),
              value: settings.errorReports,
              onChanged: (v) => settings.update(errorReports: v),
            ),
            const SizedBox(height: 8),
            Text('Apariencia', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'dark', label: Text('Oscuro'), icon: Icon(Icons.dark_mode)),
                ButtonSegment(value: 'light', label: Text('Claro'), icon: Icon(Icons.light_mode)),
                ButtonSegment(value: 'system', label: Text('Auto'), icon: Icon(Icons.brightness_auto)),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (v) => settings.update(themeMode: v.first),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                for (final c in const [0xFF00B4D8, 0xFF7C4DFF, 0xFFE91E63, 0xFF4CAF50, 0xFFFF9800])
                  GestureDetector(
                    onTap: () => settings.update(seedColor: c),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(c),
                      child: settings.seedColor == c
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (voice != null)
              ListTile(
                leading: const Icon(Icons.record_voice_over),
                title: const Text('Probar la voz de SmartBuds'),
                onTap: () => voice!.speak('Hola, soy SmartBuds. Dime qué quieres escuchar.',
                    force: true),
              ),
            const SizedBox(height: 16),
            if (voice != null) _onlyMyVoice(context),
            const SizedBox(height: 16),
            const Card(
              child: ListTile(
                leading: Icon(Icons.screen_lock_portrait),
                title: Text('Con la pantalla apagada'),
                subtitle: Text(
                    'Mientras el micrófono esté activo verás la notificación «SmartBuds está '
                    'escuchando». Puedes bloquear el teléfono o cerrar la app: sigue '
                    'escuchando hasta que toques «Detener» en la notificación.'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _onlyMyVoice(BuildContext context) {
    final v = voice!;
    final theme = Theme.of(context);
    if (!_speakerAvailable) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.person_off),
          title: Text('Solo mi voz (no disponible)'),
          subtitle: Text('Ejecuta otra vez scripts/descargar-modelo-voz.ps1 (ahora incluye '
              'el modelo de hablante) y reinstala la app.'),
        ),
      );
    }
    final trained = settings.voiceprint != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Solo mi voz', style: theme.textTheme.titleMedium),
            const Text('SmartBuds aprende cómo suena tu voz y no obedece a otras personas.'),
            const SizedBox(height: 8),
            if (v.enrolling)
              ListTile(
                leading: const CircularProgressIndicator(),
                title: Text('Di «Cambia» (${v.enrollCount + 1} de ${VoiceEngine.enrollTarget})'),
                subtitle: const Text('Con tu tono normal, como le hablarías a SmartBuds.'),
                trailing: TextButton(
                    onPressed: v.cancelEnrollment, child: const Text('Cancelar')),
              )
            else
              OutlinedButton.icon(
                onPressed: () async {
                  if (!v.enabled) await v.start();
                  if (!v.enabled) return;
                  v.startEnrollment((print) {
                    settings.update(voiceprint: print, onlyMyVoice: true);
                    v.guard.enabled = true;
                  });
                  await v.speak('Di cambia tres veces.', force: true);
                },
                icon: const Icon(Icons.record_voice_over),
                label: Text(trained ? 'Volver a entrenar mi voz' : 'Entrenar mi voz'),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Solo responder a mi voz'),
              subtitle: Text(trained ? 'Voz entrenada' : 'Primero entrena tu voz'),
              value: settings.onlyMyVoice && trained,
              onChanged: trained
                  ? (on) {
                      settings.update(onlyMyVoice: on);
                      v.guard.enabled = on;
                    }
                  : null,
            ),
            if (trained) ...[
              Text('Exigencia: ${(settings.voiceThreshold * 100).round()} %',
                  style: theme.textTheme.bodySmall),
              Slider(
                min: 0.3,
                max: 0.8,
                divisions: 10,
                value: settings.voiceThreshold.clamp(0.3, 0.8),
                onChanged: (x) {
                  settings.update(voiceThreshold: x);
                  v.guard.threshold = x;
                },
              ),
              const Text('Si a veces no te obedece, bájala. Si responde a otras personas, súbela.'),
            ],
            if (v.lastRejectedVoice)
              Text('La última frase no parecía tu voz y se ignoró.',
                  style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
    );
  }
}
