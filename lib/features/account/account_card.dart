import 'package:flutter/material.dart';

import 'supabase_auth.dart';

/// Tarjeta «Tu cuenta»: crear cuenta o entrar con correo y contraseña.
class AccountCard extends StatefulWidget {
  const AccountCard({super.key, required this.auth});

  final SupabaseAuth auth;

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hidden = true;

  SupabaseAuth get auth => widget.auth;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _valid() {
    if (!_email.text.contains('@')) {
      setState(() => auth.error = 'Escribe tu correo completo.');
      return false;
    }
    if (_password.text.length < 6) {
      setState(() => auth.error = 'La contraseña debe tener al menos 6 caracteres.');
      return false;
    }
    return true;
  }

  Future<void> _signIn() async {
    if (_valid() && await auth.signIn(_email.text, _password.text)) _password.clear();
  }

  Future<void> _signUp() async {
    if (_valid() && await auth.signUp(_email.text, _password.text)) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (auth.signedIn) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.verified_user),
              title: Text(auth.email ?? 'Cuenta activa'),
              subtitle: const Text('Tus gustos se guardan en tu cuenta y te siguen '
                  'a otro teléfono.'),
              trailing: TextButton(onPressed: auth.signOut, child: const Text('Salir')),
            ),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Tu cuenta', style: theme.textTheme.titleMedium),
                const Text('Entra para no perder tus gustos si cambias de teléfono o '
                    'reinstalas la app.'),
                const SizedBox(height: 8),
                TextField(
                  controller: _email,
                  enabled: !auth.busy,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Correo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _password,
                  enabled: !auth.busy,
                  obscureText: _hidden,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Contraseña (mínimo 6)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _hidden = !_hidden),
                    ),
                  ),
                ),
                if (auth.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(auth.error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: auth.busy ? null : _signUp,
                      child: const Text('Crear cuenta'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: auth.busy ? null : _signIn,
                      child: auth.busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Entrar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
