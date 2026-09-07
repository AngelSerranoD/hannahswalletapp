package com.hannahswallet.hannahswalletapp

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * Se extiende FlutterFragmentActivity y no FlutterActivity porque local_auth
 * levanta el BiometricPrompt de AndroidX, que es un DialogFragment y necesita
 * un FragmentManager. Con la FlutterActivity normal la biometria falla en
 * tiempo de ejecucion con "no activity" y el bloqueo de la app quedaria
 * inutilizable.
 */
class MainActivity : FlutterFragmentActivity()
