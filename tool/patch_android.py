#!/usr/bin/env python3
"""Ajusta el proyecto Android generado por `flutter create` para GYMSHERONSO:
nombre de la app, permisos, receptores de notificaciones y desugaring de Java."""
import pathlib, re, sys

app = pathlib.Path('android/app')
manifest = app / 'src/main/AndroidManifest.xml'
if not manifest.exists():
    sys.exit('No existe android/app/src/main/AndroidManifest.xml. Ejecuta primero: flutter create --platforms=android .')

t = manifest.read_text(encoding='utf-8')
perms = '''    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32"/>
'''
receivers = '''        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
'''
if 'POST_NOTIFICATIONS' not in t:
    t = t.replace('<application', perms + '    <application', 1)
    t = t.replace('</application>', receivers + '    </application>', 1)
t = re.sub(r'android:label="[^"]*"', 'android:label="GYMSHERONSO"', t, count=1)
manifest.write_text(t, encoding='utf-8')

for name in ('build.gradle.kts', 'build.gradle'):
    g = app / name
    if not g.exists():
        continue
    s = g.read_text(encoding='utf-8')
    if 'coreLibraryDesugaring' in s:
        break
    if name.endswith('.kts'):
        s = s.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
        s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    else:
        s = s.replace('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true', 1)
        s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    g.write_text(s, encoding='utf-8')
    break
print('Android parcheado para GYMSHERONSO')
