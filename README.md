## Запуск приложения

1. В Firebase Console включите провайдер **Email/Password** в Authentication.
2. Установите Android SDK API 36 для Android-сборки, затем зависимости и запустите Flutter:

   ```sh
   flutter pub get
   flutter run
   ```

3. Настройте FCM/APNs для целевых платформ. Для веб-сборки задайте публичный VAPID key из Firebase Console:

   ```sh
   flutter run -d chrome --dart-define=FCM_VAPID_KEY=<ваш-vapid-key>
   ```

   На Windows/Linux приложение не запрашивает FCM-токен.

Firebase project options уже сгенерированы для подключённого проекта в `firebase_options.dart`. Не публикуйте приватные ключи сервисных аккаунтов; клиентские Firebase options не заменяют Security Rules.
