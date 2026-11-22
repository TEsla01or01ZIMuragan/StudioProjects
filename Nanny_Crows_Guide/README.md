# Школьный дневник

Flutter-приложение с Firebase для учеников, родителей и учителей. Интерфейс разделён по ролям; Firebase Auth отвечает за вход, Firestore — за данные, Storage — за файлы, Cloud Functions — за коды привязки и push-уведомления.

## Структура

```text
lib/
├── core/                         # Тема, маршрутизация и общие providers
└── features/
    ├── auth/                     # Регистрация, вход, профиль пользователя
    ├── home/presentation/        # Навигация и ролевые экраны
    └── school/
        ├── data/                 # Firestore/Storage/Functions репозиторий
        └── domain/               # Модели расписания и работ
functions/src/                    # Доверенная серверная логика
firestore.rules                   # Правила доступа Firestore
storage.rules                     # Правила доступа к файлам
```

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

## Подготовка данных школы

Создание классов, предметов и назначение учеников классам должны выполняться доверенным администратором через Firebase Console или Admin SDK. Пользователь не может назначить себе `classId`, поменять свою роль, создавать классы или предметы.

- `classes/{classId}`: `name`, `teacherIds` (массив UID учителей).
- `subjects/{subjectId}`: `name`, `classId`, `teacherId`.
- `users/{studentUid}`: роль `student` и при зачислении `classId`.
- `users/{teacherUid}`: роль `teacher`.
- Профили родителей создаются в приложении; функция привязки поддерживает `childrenIds` и производное поле `childClassIds`.

Для создания задания преподаватель указывает существующие ID класса и предмета. Правила проверяют назначение преподавателя на класс и предмет. При смене класса ученика Cloud Function обновляет списки классов связанных родителей.

## Firebase Functions и правила

Требуется Node.js 22 и Firebase CLI. Из каталога проекта выполните:

```sh
cd functions
npm ci
npm run build
cd ..
firebase deploy --only firestore:rules,firestore:indexes,storage,functions
```

Functions генерируют уникальный шестизначный код ученика, связывают родителя с учеником через callable function с ограничением частоты попыток, синхронизируют доступ родителя к классам, обновляют средний балл предмета и отправляют FCM-уведомления о новых заданиях и выставленных оценках.

Правила запрещают родителю изменять школьные данные, ученику — менять оценку, а учителю — оценивать работы вне своих классов. Коллекции `inviteCodes` и `inviteAttempts` доступны только Cloud Functions.

После изменений в `firestore.rules` или `firestore.indexes.json` опубликуйте их в проекте Firebase. Из каталога проекта выполните:

```sh
firebase deploy --only firestore:rules,firestore:indexes --project nanny-crow-s-guide
```

Либо опубликуйте содержимое `firestore.rules` в Firebase Console → Firestore Database → Rules, а составные индексы из `firestore.indexes.json` создайте на вкладке **Indexes**. Пока правила не опубликованы, регистрация может завершаться сообщением `PERMISSION_DENIED`; после создания индексов дождитесь статуса **Enabled**.

## Проверки

```sh
flutter analyze
flutter test
```

Cloud Functions:

```sh
cd functions
npm run build
```
